defmodule Kerosene do
  defstruct items: [], per_page: 0, max_page: 0, page: 0, total_pages: 0, total_count: 0, params: []
  import Ecto.Query

  @per_page 10
  @max_page 100
  @page 1

  @moduledoc """
  Pagination for Ecto and Phoenix.
  """

  defmacro __using__(opts \\ []) do
    quote do
      def paginate(query, params \\ %{}, options \\ []) do
        Kerosene.paginate( __MODULE__, query, params,
          Keyword.merge(unquote(opts), options))
      end
    end
  end

  def paginate(repo, query, params, opts) do
    paginate(repo, query, build_options(opts, params))
  end

  def paginate(repo, query, opts) do
    per_page = Keyword.get(opts, :per_page)
    max_page = Keyword.get(opts, :max_page)
    total_count = get_total_count(opts[:total_count], repo, query)
    total_pages = get_total_pages(total_count, per_page)
    page = get_page(opts, total_pages)
    offset = get_offset(total_count, page, per_page)

    kerosene = %Kerosene {
      per_page: per_page,
      page: page,
      total_pages: total_pages,
      total_count: total_count,
      max_page: max_page,
      params: opts[:params]
    }

    {get_items(repo, query, per_page, offset), kerosene}
  end

  defp get_items(repo, query, nil, _), do: repo.all(query)
  defp get_items(repo, query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^offset)
    |> repo.all
  end

  defp get_offset(total_pages, page, per_page) do
    page = case page > total_pages do
      true -> total_pages
      _ -> page
    end

    case page > 0 do
      true -> (page - 1) * per_page
      _ -> 0
    end
  end

  defp get_total_count(count, _repo, _query) when is_integer(count) and count >= 0, do: count

  defp get_total_count(_count, repo, query) do
    total_pages =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> total_count()
      |> repo.one()

    total_pages || 0
  end

  defp total_count(query = %{group_bys: [_|_]}), do: total_row_count(query)
  defp total_count(query = %{from: %Ecto.Query.FromExpr{source: {_, nil}}}), do: total_row_count(query)

  defp total_count(query) do
    primary_key = get_primary_key(query)
    query
    |> exclude(:select)
    |> select([i], count(field(i, ^primary_key), :distinct))
  end

  defp total_row_count(query) do
    query
    |> subquery()
    |> select(count("*"))
  end

  def get_primary_key(query) do
    new_query = case is_map(query) do
      true ->
        case query.from do
          %Ecto.Query.FromExpr{source: {_, from}} -> from
          {source, _schema} -> source
        end
      _ -> query
    end

    new_query
    |> apply(:__schema__, [:primary_key])
    |> hd
  end

  def get_total_pages(_, nil), do: 1
  def get_total_pages(count, per_page) do
    Float.ceil(count / per_page) |> trunc()
  end

  def get_page(params, total_pages) do
    case params[:page] > params[:max_page] do
      true -> total_pages
      _ -> params[:page]
    end
  end

  defp build_options(opts, params) do
    page = Map.get(params, "page", @page) |> to_integer()
    per_page = default_per_page(opts) |> to_integer()
    max_page = Keyword.get(opts, :max_page, default_max_page())
    Keyword.merge(opts, [page: page, per_page: per_page, params: params, max_page: max_page])
  end

  defp default_per_page(opts) do
    case Keyword.get(opts, :per_page) do
      nil -> Application.get_env(:kerosene, :per_page, @per_page)
      per_page -> per_page
    end
  end

  defp default_max_page() do
    Application.get_env(:kerosene, :max_page, @max_page)
  end

  def to_integer(i) when is_integer(i), do: abs(i)
  def to_integer(i) when is_binary(i) do
    case Integer.parse(i) do
      {n, _} -> n
      _ -> 0
    end
  end
  def to_integer(_), do: @page
end
