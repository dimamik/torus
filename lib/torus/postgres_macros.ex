defmodule Torus.PostgresMacros do
  @moduledoc false
  @default_language "english"

  @doc false
  defmacro to_tsquery_dynamic(column, query_text, language \\ @default_language) do
    quote do
      fragment(
        "
        CASE
            WHEN trim(websearch_to_tsquery(?, ?)::text) = '' THEN FALSE
            ELSE to_tsvector(?, ?) @@ (websearch_to_tsquery(?, ?)::text || ':*')::tsquery
        END
        ",
        unquote(language),
        unquote(query_text),
        unquote(language),
        unquote(column),
        unquote(language),
        unquote(query_text)
      )
    end
  end
end
