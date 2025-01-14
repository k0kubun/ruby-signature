class StringTest < StdlibTest
  target String
  using hook.refinement

  def test_gsub
    s = "string"
    s.gsub(/./, "")
    s.gsub("a", "b")
    s.gsub(/./) {|x| "" }
    s.gsub(/./, {"foo" => "bar"})
    s.gsub(/./)
    s.gsub("")
  end

  def test_bytesize
    s = "string"
    s.bytesize
  end

  def delete_prefix
    "foo".delete_prefix("f")
  end

  def delete_prefix!
    "foo".delete_prefix! "f"
    "foo".delete_prefix! "a"
  end

  def delete_suffix
    "foo".delete_suffix "o"
  end

  def delete_suffix!
    "foo".delete_suffix! "o"
    "foo".delete_suffix! "a"
  end

  def test_endwith
    s = "string"
    s.end_with?
    s.end_with?("foo")
  end

  def test_force_encoding
    s = ""
    s.force_encoding "ASCII-8BIT"
    s.force_encoding Encoding::ASCII_8BIT
  end

  def test_include
    "".include?("")
  end

  def test_initialize
    String.new
    String.new("")
    String.new("", encoding: Encoding::ASCII_8BIT)
    String.new("", encoding: Encoding::ASCII_8BIT, capacity: 123)
    String.new(encoding: Encoding::ASCII_8BIT, capacity: 123)
  end

  def test_succ
    "".succ
  end

  def test_succ!
    "".succ
  end

  def test_encode
    s = "string"
    s.encode("ascii")
    s.encode("ascii", Encoding::ASCII_8BIT)
    s.encode(Encoding::ASCII_8BIT, "ascii")
    s.encode("ascii", invalid: :replace)
    s.encode(Encoding::ASCII_8BIT, Encoding::ASCII_8BIT, undef: nil)
    s.encode(
      invalid: nil,
      undef: :replace,
      replace: "foo",
      fallback: {"a" => "a"},
      xml: :text,
      universal_newline: true,
    )
    s.encode(cr_newline: true)
    s.encode(crlf_newline: true)
  end

  def test_encode!
    s = "string"
    s.encode!("ascii")
    s.encode!("ascii", Encoding::ASCII_8BIT)
    s.encode!(Encoding::ASCII_8BIT, "ascii")
    s.encode!("ascii", invalid: :replace)
    s.encode!(Encoding::ASCII_8BIT, Encoding::ASCII_8BIT, undef: nil)
    s.encode!(
      invalid: nil,
      undef: :replace,
      replace: "foo",
      fallback: {"a" => "a"},
      xml: :text,
      universal_newline: true,
    )
    s.encode!(cr_newline: true)
    s.encode!(crlf_newline: true)
  end
end
