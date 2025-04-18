defmodule Torus.PatternMatchTest do
  use Torus.Case, async: true

  describe "sanitize/1" do
    test "sanitizes the input string" do
      assert "foo" = Torus.sanitize("%foo%")
      assert "foo" = Torus.sanitize("_foo_")
      assert "foo" = Torus.sanitize("_foo\\")
      assert "foobar" = Torus.sanitize("_foo\\bar")
      assert "foo|bar" = Torus.sanitize("_foo|bar")
    end
  end
end
