defmodule Torus.HighlightTest do
  @moduledoc false
  use Torus.Case, async: true

  describe "highlight/3" do
    test "wraps matches in <b> tags by default" do
      insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")

      assert ["Hogwarts <b>Shocker</b>"] =
               Post
               |> Torus.full_text([p], [p.title, p.body], "shocker")
               |> select([p], Torus.highlight(p.title, "shocker"))
               |> Repo.all()
    end

    test "highlights prefix matches by default" do
      insert_post!(title: "Diagon Bombshell")

      assert ["Diagon <b>Bombshell</b>"] =
               Post
               |> Torus.full_text([p], [p.title], "bombsh")
               |> select([p], Torus.highlight(p.title, "bombsh"))
               |> Repo.all()
    end

    test "prefix_search: false only highlights full-word matches" do
      insert_post!(title: "Diagon Bombshell")

      assert ["Diagon Bombshell"] =
               Post
               |> select([p], Torus.highlight(p.title, "bombsh", prefix_search: false))
               |> Repo.all()
    end

    test "returns the document unchanged for an empty term" do
      insert_post!(title: "Hogwarts Shocker")

      assert ["Hogwarts Shocker"] =
               Post
               |> select([p], Torus.highlight(p.title, ""))
               |> Repo.all()
    end

    test "highlights multiple matches across the document" do
      insert_post!(body: "Magic is magic, and magic wins.")

      assert ["<b>Magic</b> is <b>magic</b>, and <b>magic</b> wins."] =
               Post
               |> select([p], Torus.highlight(p.body, "magic"))
               |> Repo.all()
    end

    test ":start_sel and :stop_sel customize the wrapping" do
      insert_post!(title: "Hogwarts Shocker")

      assert ["Hogwarts @@Shocker@@"] =
               Post
               |> select(
                 [p],
                 Torus.highlight(p.title, "shocker", start_sel: "@@", stop_sel: "@@")
               )
               |> Repo.all()
    end

    test "highlight_all: false returns a snippet" do
      insert_post!(body: "A magic spell disrupts the Quidditch Cup final at Hogwarts.")

      assert ["<b>Quidditch</b> Cup final"] =
               Post
               |> select(
                 [p],
                 Torus.highlight(p.body, "quidditch",
                   highlight_all: false,
                   max_words: 5,
                   min_words: 2
                 )
               )
               |> Repo.all()
    end

    test "supports select_merge and other search types" do
      insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")

      assert [%{title: "Diagon <b>Bombshell</b>"}] =
               Post
               |> Torus.similarity([p], [p.title], "bombshell", pre_filter: true)
               |> select([p], %{body: p.body})
               |> select_merge([p], %{title: Torus.highlight(p.title, "bombshell")})
               |> Repo.all()
    end

    test ":language is applied to stemming" do
      insert_post!(title: "magiens mest eftersøgte hekse")

      assert ["<b>magiens</b> mest eftersøgte hekse"] =
               Post
               |> select([p], Torus.highlight(p.title, "magien", language: "danish"))
               |> Repo.all()
    end

    test "type: :substring highlights inside words, pairs with ilike" do
      insert_post!(title: "Hogwarts Shocker")

      assert ["H<b>ogwart</b>s Shocker"] =
               Post
               |> Torus.ilike([p], [p.title], "%ogwart%")
               |> select([p], Torus.highlight(p.title, "ogwart", type: :substring))
               |> Repo.all()
    end

    test "type: :substring is case-insensitive by default and highlights all occurrences" do
      insert_post!(title: "Magic is MAGIC")

      assert ["<b>Magic</b> is <b>MAGIC</b>"] =
               Post
               |> select([p], Torus.highlight(p.title, "magic", type: :substring))
               |> Repo.all()
    end

    test "type: :substring with case_sensitive: true only highlights exact case" do
      insert_post!(title: "Magic is MAGIC")

      assert ["Magic is <b>MAGIC</b>"] =
               Post
               |> select(
                 [p],
                 Torus.highlight(p.title, "MAGIC", type: :substring, case_sensitive: true)
               )
               |> Repo.all()
    end

    test "type: :substring escapes regex metacharacters in the term" do
      insert_post!(title: "Learning C++ (the hard way)")

      assert ["Learning <b>C++</b> (the hard way)"] =
               Post
               |> select([p], Torus.highlight(p.title, "c++", type: :substring))
               |> Repo.all()
    end

    test "type: :substring returns the document unchanged for an empty term" do
      insert_post!(title: "Hogwarts Shocker")

      assert ["Hogwarts Shocker"] =
               Post
               |> select([p], Torus.highlight(p.title, "", type: :substring))
               |> Repo.all()
    end

    test "type: :substring respects custom selectors" do
      insert_post!(title: "Hogwarts Shocker")

      assert ["Hogwarts @@Shocker@@"] =
               Post
               |> select(
                 [p],
                 Torus.highlight(p.title, "shocker",
                   type: :substring,
                   start_sel: "@@",
                   stop_sel: "@@"
                 )
               )
               |> Repo.all()
    end

    test "raises on invalid options" do
      assert_raise RuntimeError, ~r/term_function/, fn ->
        defmodule InvalidHighlightOptions do
          import Ecto.Query
          alias TorusTest.Post

          def query do
            select(Post, [p], Torus.highlight(p.title, "term", term_function: :invalid))
          end
        end
      end
    end
  end

  describe ":highlight option on search macros" do
    test "full_text/5 highlights into the struct's own key" do
      insert_post!(title: "Hogwarts Shocker")

      assert [%Post{title: "Hogwarts <b>Shocker</b>"}] =
               Post
               |> Torus.full_text([p], [p.title], "shocker", highlight: [title: p.title])
               |> Repo.all()
    end

    test "full_text/5 highlights into a selected map with several columns" do
      insert_post!(title: "Hogwarts Shocker", body: "A shocker at Hogwarts.")

      assert [%{title: "Hogwarts <b>Shocker</b>", body: "A <b>shocker</b> at Hogwarts."}] =
               Post
               |> select([p], %{})
               |> Torus.full_text([p], [p.title, p.body], "shocker",
                 highlight: [title: p.title, body: p.body]
               )
               |> Repo.all()
    end

    test "ilike/5 strips wildcards and highlights the substring" do
      insert_post!(title: "Hogwarts Shocker")

      assert [%Post{title: "H<b>ogwart</b>s Shocker"}] =
               Post
               |> Torus.ilike([p], [p.title], "%ogwart%", highlight: [title: p.title])
               |> Repo.all()
    end

    test "like/5 highlights case-sensitively" do
      insert_post!(title: "MAGIC magic")

      assert [%Post{title: "MAGIC <b>magic</b>"}] =
               Post
               |> Torus.like([p], [p.title], "%magic%", highlight: [title: p.title])
               |> Repo.all()
    end

    test "similarity/5 highlights exact-word matches" do
      insert_post!(title: "Diagon Bombshell")

      assert [%Post{title: "Diagon <b>Bombshell</b>"}] =
               Post
               |> Torus.similarity([p], [p.title], "bombshell", highlight: [title: p.title])
               |> Repo.all()
    end

    test "hybrid/4 highlights each branch's term matches" do
      insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")

      assert [
               %{
                 title: "Diagon <b>Bombshell</b>",
                 body: "Secrets <b>uncovered</b> in the heart of Hogwarts."
               },
               %{title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup."}
             ] =
               Post
               |> select([p], %{})
               |> Torus.hybrid([p],
                 full_text: {[p.title, p.body], "uncov", highlight: [body: p.body]},
                 similarity: {[p.title], "bombshell", highlight: [title: p.title]}
               )
               |> Repo.all()
    end

    test "hybrid/4 raises when a semantic branch has :highlight" do
      assert_raise RuntimeError, ~r/semantic/, fn ->
        defmodule InvalidSemanticHighlight do
          import Ecto.Query
          import Torus
          alias TorusTest.Post

          def query(vector) do
            Torus.hybrid(Post, [p], semantic: {p.embedding, vector, highlight: [title: p.title]})
          end
        end
      end
    end

    test "raises when :highlight is not a keyword list" do
      assert_raise RuntimeError, ~r/keyword list/, fn ->
        defmodule InvalidHighlightShape do
          import Ecto.Query
          import Torus
          alias TorusTest.Post

          def query do
            Torus.full_text(Post, [p], [p.title], "term", highlight: p.title)
          end
        end
      end
    end
  end
end
