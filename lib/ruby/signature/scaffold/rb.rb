module Ruby
  module Signature
    module Scaffold
      class RB
        attr_reader :source_decls
        attr_reader :toplevel_members

        def initialize
          @source_decls = []
          @toplevel_members = []
        end

        def decls
          decls = []

          decls.push(*source_decls)

          unless toplevel_members.empty?
            top = AST::Declarations::Extension.new(
              name: TypeName.new(name: :Object, namespace: Namespace.empty),
              extension_name: :Toplevel,
              members: toplevel_members,
              annotations: [],
              comment: nil,
              location: nil,
              type_params: AST::Declarations::ModuleTypeParams.empty
            )
            decls << top
          end

          decls
        end

        def parse(string)
          comments = Ripper.lex(string).yield_self do |tokens|
            tokens.each.with_object({}) do |token, hash|
              if token[1] == :on_comment
                line = token[0][0]
                body = token[2][2..]

                body = "\n" if body.empty?

                comment = AST::Comment.new(string: body, location: nil)
                if (prev_comment = hash[line - 1])
                  hash[line - 1] = nil
                  hash[line] = AST::Comment.new(string: prev_comment.string + comment.string,
                                                location: nil)
                else
                  hash[line] = comment
                end
              end
            end
          end

          process RubyVM::AbstractSyntaxTree.parse(string), namespace: Namespace.empty, current_module: nil, comments: comments
        end

        def nested_name(name)
          (current_namespace + const_to_name(name).to_namespace).to_type_name.relative!
        end

        def process(node, namespace:, current_module:, comments:)
          case node.type
          when :CLASS
            class_name, super_class, *class_body = node.children
            kls = AST::Declarations::Class.new(
              name: const_to_name(class_name).with_prefix(namespace).relative!,
              super_class: super_class && AST::Declarations::Class::Super.new(name: const_to_name(super_class), args: []),
              type_params: AST::Declarations::ModuleTypeParams.empty,
              members: [],
              annotations: [],
              location: nil,
              comment: comments[node.first_lineno - 1]
            )

            source_decls.push kls

            each_node class_body do |child|
              process child, namespace: kls.name.to_namespace, current_module: kls, comments: comments
            end
          when :MODULE
            module_name, *module_body = node.children

            mod = AST::Declarations::Module.new(
              name: const_to_name(module_name).with_prefix(namespace).relative!,
              type_params: AST::Declarations::ModuleTypeParams.empty,
              self_type: nil,
              members: [],
              annotations: [],
              location: nil,
              comment: comments[node.first_lineno - 1]
            )

            source_decls.push mod

            each_node module_body do |child|
              process child, namespace: mod.name.to_namespace, current_module: mod, comments: comments
            end

          when :DEFN, :DEFS
              if node.type == :DEFN
                def_name, def_body = node.children
                kind = :instance
              else
                _, def_name, def_body = node.children
                kind = :singleton
              end

              types = [
                MethodType.new(
                  type_params: [],
                  type: function_type_from_body(def_body),
                  block: block_from_body(def_body),
                  location: nil
                )
              ]

              member = AST::Members::MethodDefinition.new(
                name: def_name,
                location: nil,
                annotations: [],
                types: types,
                kind: kind,
                comment: comments[node.first_lineno - 1],
                attributes: []
              )

              if current_module
                current_module.members.push member
              else
                toplevel_members.push member
              end
          when :FCALL
            if current_module
              # Inside method definition cannot reach here.
              args = node.children[1].children

              case node.children[0]
              when :include
                args.each do |arg|
                  if (name = const_to_name(arg))
                    current_module.members << AST::Members::Include.new(
                      name: name,
                      args: [],
                      annotations: [],
                      location: nil,
                      comment: comments[node.first_lineno - 1]
                    )
                  end
                end
              when :extend
                args.each do |arg|
                  if (name = const_to_name(arg))
                    current_module.members << AST::Members::Extend.new(
                      name: name,
                      args: [],
                      annotations: [],
                      location: nil,
                      comment: comments[node.first_lineno - 1]
                    )
                  end
                end
              when :attr_reader
                args.each do |arg|
                  if arg&.type == :LIT && arg.children[0].is_a?(Symbol)
                    current_module.members << AST::Members::AttrReader.new(
                      name: arg.children[0],
                      ivar_name: nil,
                      type: Types::Bases::Any.new(location: nil),
                      location: nil,
                      comment: comments[node.first_lineno - 1],
                      annotations: []
                    )
                  end
                end
              when :attr_accessor
                args.each do |arg|
                  if arg&.type == :LIT && arg.children[0].is_a?(Symbol)
                    current_module.members << AST::Members::AttrAccessor.new(
                      name: arg.children[0],
                      ivar_name: nil,
                      type: Types::Bases::Any.new(location: nil),
                      location: nil,
                      comment: comments[node.first_lineno - 1],
                      annotations: []
                    )
                  end
                end
              when :attr_writer
                args.each do |arg|
                  if arg&.type == :LIT && arg.children[0].is_a?(Symbol)
                    current_module.members << AST::Members::AttrWriter.new(
                      name: arg.children[0],
                      ivar_name: nil,
                      type: Types::Bases::Any.new(location: nil),
                      location: nil,
                      comment: comments[node.first_lineno - 1],
                      annotations: []
                    )
                  end
                end
              end
            end

          when :CDECL
            type_name = case
                        when node.children[0].is_a?(Symbol)
                          ns = if current_module
                                 current_module.name.to_namespace
                               else
                                 Namespace.empty
                               end
                          TypeName.new(name: node.children[0], namespace: ns)
                        else
                          name = const_to_name(node.children[0])
                          if current_module
                            name.with_prefix current_module.name.to_namespace
                          else
                            name
                          end.relative!
                        end

            source_decls << AST::Declarations::Constant.new(
              name: type_name,
              type: node_type(node.children.last),
              location: nil,
              comment: comments[node.first_lineno - 1]
            )
          else
            each_child node do |child|
              process child, namespace: namespace, current_module: current_module, comments: comments
            end
          end
        end

        def const_to_name(node)
          case node&.type
          when :CONST
            TypeName.new(name: node.children[0], namespace: Namespace.empty)
          when :COLON2
            if node.children[0]
              namespace = const_to_name(node.children[0]).to_namespace
            else
              namespace = Namespace.empty
            end

            TypeName.new(name: node.children[1], namespace: namespace)
          when :COLON3
            TypeName.new(name: node.children[0], namespace: Namespace.root)
          end
        end

        def each_node(nodes)
          nodes.each do |child|
            if child.is_a?(RubyVM::AbstractSyntaxTree::Node)
              yield child
            end
          end
        end

        def each_child(node, &block)
          each_node node.children, &block
        end

        def function_type_from_body(node)
          table_node, args_node, *_ = node.children

          pre_num, _pre_init, opt, _first_post, post_num, _post_init, rest, kw, kwrest, _block = args_node.children

          untyped = Types::Bases::Any.new(location: nil)

          fun = Types::Function.empty(untyped)

          table_node.take(pre_num).each do |name|
            fun.required_positionals << Types::Function::Param.new(name: name, type: untyped)
          end

          while opt&.type == :OPT_ARG
            lvasgn, opt = opt.children
            name = lvasgn.children[0]
            fun.optional_positionals << Types::Function::Param.new(
              name: name,
              type: node_type(lvasgn.children[1])
            )
          end

          if rest
            fun = fun.update(rest_positionals: Types::Function::Param.new(name: rest, type: untyped))
          end

          table_node.drop(fun.required_positionals.size + fun.optional_positionals.size + (fun.rest_positionals ? 1 : 0)).take(post_num).each do |name|
            fun.trailing_positionals << Types::Function::Param.new(name: name, type: untyped)
          end

          while kw
            lvasgn, kw = kw.children
            name, value = lvasgn.children

            case value
            when nil, :NODE_SPECIAL_REQUIRED_KEYWORD
              fun.required_keywords[name] = Types::Function::Param.new(name: name, type: untyped)
            when RubyVM::AbstractSyntaxTree::Node
              fun.optional_keywords[name] = Types::Function::Param.new(name: name, type: node_type(value))
            else
              raise "Unexpected keyword arg value: #{value}"
            end
          end

          if kwrest
            fun = fun.update(rest_keywords: Types::Function::Param.new(name: kwrest.children[0], type: untyped))
          end

          fun
        end

        def block_from_body(node)
          _, args_node, body_node = node.children

          _pre_num, _pre_init, _opt, _first_post, _post_num, _post_init, _rest, _kw, _kwrest, block = args_node.children

          untyped = Types::Bases::Any.new(location: nil)

          method_block = nil

          if block
            method_block = MethodType::Block.new(
              required: true,
              type: Types::Function.empty(untyped)
            )
          end

          if body_node
            if (yields = any_node?(body_node) {|n| n.type == :YIELD })
              method_block = MethodType::Block.new(
                required: true,
                type: Types::Function.empty(untyped)
              )

              yields.each do |yield_node|
                array_content = yield_node.children[0].children.compact

                positionals, keywords = if keyword_hash?(array_content.last)
                                          [array_content.take(array_content.size - 1), array_content.last]
                                        else
                                          [array_content, nil]
                                        end

                if (diff = positionals.size - method_block.type.required_positionals.size) > 0
                  diff.times do
                    method_block.type.required_positionals << Types::Function::Param.new(
                      type: untyped,
                      name: nil
                    )
                  end
                end

                if keywords
                  keywords.children[0].children.each_slice(2) do |key_node, value_node|
                    if key_node
                      key = key_node.children[0]
                      method_block.type.required_keywords[key] ||=
                        Types::Function::Param.new(
                          type: untyped,
                          name: nil
                        )
                    end
                  end
                end
              end
            end
          end

          method_block
        end

        def keyword_hash?(node)
          if node
            if node.type == :HASH
              node.children[0].children.compact.each_slice(2).all? {|key, _|
                key.type == :LIT && key.children[0].is_a?(Symbol)
              }
            end
          end
        end

        def any_node?(node, nodes: [], &block)
          if yield(node)
            nodes << node
          end

          each_child node do |child|
            any_node? child, nodes: nodes, &block
          end

          nodes.empty? ? nil : nodes
        end

        def node_type(node, default: Types::Bases::Any.new(location: nil))
          case node.type
          when :LIT
            case node.children[0]
            when Symbol
              BuiltinNames::Symbol.instance_type
            when Integer
              BuiltinNames::Integer.instance_type
            when Float
              BuiltinNames::Float.instance_type
            else
              default
            end
          when :STR, :DSTR
            BuiltinNames::String.instance_type
          when :NIL
            # This type is technical non-sense, but may help practically.
            Types::Optional.new(
              type: Types::Bases::Any.new(location: nil),
              location: nil
            )
          when :TRUE, :FALSE
            Types::Bases::Bool.new(location: nil)
          when :ARRAY, :LIST
            BuiltinNames::Array.instance_type(default)
          when :HASH
            BuiltinNames::Hash.instance_type(default, default)
          else
            default
          end
        end
      end
    end
  end
end
