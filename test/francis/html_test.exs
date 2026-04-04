defmodule Francis.HTMLTest do
  use ExUnit.Case, async: true

  alias Francis.HTML

  describe "escape/1" do
    test "returns empty string for nil" do
      assert HTML.escape(nil) == ""
    end

    test "returns the same string when no special characters" do
      assert HTML.escape("Hello, World!") == "Hello, World!"
    end

    test "escapes ampersand" do
      assert HTML.escape("foo & bar") == "foo &amp; bar"
    end

    test "escapes less-than sign" do
      assert HTML.escape("a < b") == "a &lt; b"
    end

    test "escapes greater-than sign" do
      assert HTML.escape("a > b") == "a &gt; b"
    end

    test "escapes double quotes" do
      assert HTML.escape(~s(a "quoted" value)) == "a &quot;quoted&quot; value"
    end

    test "escapes single quotes" do
      assert HTML.escape("it's") == "it&#39;s"
    end

    test "escapes script tags to prevent XSS" do
      assert HTML.escape("<script>alert('xss')</script>") ==
               "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
    end

    test "escapes multiple special characters in one string" do
      assert HTML.escape(~s(<a href="test&foo">click</a>)) ==
               "&lt;a href=&quot;test&amp;foo&quot;&gt;click&lt;/a&gt;"
    end

    test "handles empty string" do
      assert HTML.escape("") == ""
    end

    test "handles string with only special characters" do
      assert HTML.escape("<>&\"'") == "&lt;&gt;&amp;&quot;&#39;"
    end

    test "preserves unicode characters" do
      assert HTML.escape("héllo wörld") == "héllo wörld"
    end

    test "escapes mixed content with unicode" do
      assert HTML.escape("<b>héllo</b>") == "&lt;b&gt;héllo&lt;/b&gt;"
    end
  end
end
