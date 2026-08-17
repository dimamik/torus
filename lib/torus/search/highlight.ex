defmodule Torus.Search.Highlight do
  @moduledoc false
  import Torus.Search.Common

  @term_functions ~w[websearch_to_tsquery plainto_tsquery phraseto_tsquery]a
  @true_false ~w[true false]a
  @headline_options [
    start_sel: "StartSel",
    stop_sel: "StopSel",
    highlight_all: "HighlightAll",
    max_words: "MaxWords",
    min_words: "MinWords",
    short_word: "ShortWord",
    max_fragments: "MaxFragments",
    fragment_delimiter: "FragmentDelimiter"
  ]

  def highlight(qualifier, term, opts) do
    case get_arg!(opts, :type, :word, ~w[word substring]a) do
      :word -> word_highlight(qualifier, term, opts)
      :substring -> substring_highlight(qualifier, term, opts)
    end
  end

  def merge_highlight(query_ast, bindings, term, opts, type) do
    case Keyword.get(opts, :highlight) do
      nil ->
        query_ast

      qualifiers ->
        raise_if(
          not (is_list(qualifiers) and qualifiers != [] and
                 Enum.all?(qualifiers, &match?({key, _} when is_atom(key), &1))),
          "`:highlight` should be a keyword list of result keys to columns, " <>
            "e.g. `highlight: [title: p.title]`"
        )

        pairs = highlight_pairs(qualifiers, term, opts, type)

        quote do
          select_merge(
            unquote(query_ast),
            [unquote_splicing(bindings)],
            %{unquote_splicing(pairs)}
          )
        end
    end
  end

  defp highlight_pairs(qualifiers, term, opts, :word) do
    for {key, qualifier} <- qualifiers, do: {key, word_highlight(qualifier, term, opts)}
  end

  defp highlight_pairs(qualifiers, term, opts, :substring) do
    for {key, qualifier} <- qualifiers, do: {key, substring_highlight(qualifier, term, opts)}
  end

  defp substring_highlight(qualifier, term, opts) do
    case_sensitive = get_arg!(opts, :case_sensitive, false, @true_false)
    start_sel = Keyword.get(opts, :start_sel, "<b>")
    stop_sel = Keyword.get(opts, :stop_sel, "</b>")
    flags = if case_sensitive, do: "g", else: "gi"
    replacement = "#{start_sel}\\1#{stop_sel}"

    # Empty terms need special handling: an empty pattern matches at every position
    headline_string = """
    CASE
        WHEN ? = '' THEN ?
        ELSE regexp_replace(?, ?, ?, '#{flags}')
    END
    """

    quote do
      fragment(
        unquote(headline_string),
        ^unquote(term),
        unquote(qualifier),
        unquote(qualifier),
        ^unquote(__MODULE__).substring_pattern(unquote(term)),
        ^unquote(replacement)
      )
    end
  end

  def substring_pattern(term) when is_binary(term) do
    "(" <> Regex.escape(term) <> ")"
  end

  defp word_highlight(qualifier, term, opts) do
    language = get_language(opts)
    term_function = get_arg!(opts, :term_function, :websearch_to_tsquery, @term_functions)
    prefix_search = get_arg!(opts, :prefix_search, true, @true_false)
    headline_options = headline_options(opts)

    if prefix_search do
      # Empty terms need special handling: `''::text || ':*'` is not a valid tsquery
      headline_string = """
      CASE
          WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN ?
          ELSE ts_headline(#{language}, ?, (#{term_function}(#{language}, ?)::text || ':*')::tsquery, ?)
      END
      """

      quote do
        fragment(
          unquote(headline_string),
          ^unquote(term),
          unquote(qualifier),
          unquote(qualifier),
          ^unquote(term),
          ^unquote(headline_options)
        )
      end
    else
      headline_string = "ts_headline(#{language}, ?, #{term_function}(#{language}, ?), ?)"

      quote do
        fragment(
          unquote(headline_string),
          unquote(qualifier),
          ^unquote(term),
          ^unquote(headline_options)
        )
      end
    end
  end

  defp headline_options(opts) do
    [start_sel: "<b>", stop_sel: "</b>", highlight_all: true]
    |> Keyword.merge(Keyword.take(opts, Keyword.keys(@headline_options)))
    |> Enum.map_join(", ", fn {key, value} ->
      value = value |> to_string() |> String.replace("\"", "\"\"")
      "#{Keyword.fetch!(@headline_options, key)}=\"#{value}\""
    end)
  end
end
