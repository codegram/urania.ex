defmodule UraniaTest do
  use ExUnit.Case
  doctest Urania

  defmodule HttpSource do
    defstruct [:url, :params, :response]
  end

  defimpl Urania.DataSource, for: HttpSource do
    def identity(this) do
      [this.url, this.params]
    end

    def fetch(this, _env) do
      %{body: this.response}
    end
  end

  defmodule BatchableHttpSource do
    defstruct [:url, :params, :response]
  end

  defimpl Urania.DataSource, for: BatchableHttpSource do
    def identity(this) do
      [this.url, this.params]
    end

    def fetch(this, _env) do
      %{body: this.response}
    end
  end

  defimpl Urania.BatchedSource, for: BatchableHttpSource do
    def fetch_multi(r, rs, _env) do
      responses = for x <- [r | rs], do: %{body: Map.put(x.response, :batched, true)}
      Enum.reduce(
        Enum.zip(Enum.map([r | rs], fn req -> [req.url, req.params] end), responses),
        %{},
        fn ({id, response}, acc) -> Map.put(acc, id, response) end)
    end
  end

  test "Simple data source" do
    muse = %HttpSource { url: "google.com/foo", params: %{foo: :bar}, response: %{good: :job}}
    assert {:ok, %{body: %{good: :job}}} == Urania.run!(muse)
  end

  test "data source with transformations" do
    ds = %HttpSource { url: "google.com/foo", params: %{foo: :bar}, response: %{good: :job}}
    muse = Urania.collect([ds, Urania.value(3)])
           |> Urania.map(fn ([body, number]) -> Map.put(body, :number, number) end)
           |> Urania.map(fn last_map -> Map.put(last_map, :haha, :foo) end)
    assert {:ok, %{body: %{good: :job}, number: 3, haha: :foo}} == Urania.run!(muse)
  end

  test "multiple data sources without batching" do
    r1 = %HttpSource { url: "google.com/foo", params: %{foo: :bar}, response: %{good: :job}}
    r2 = %HttpSource { url: "google.com/bar", params: %{foo: :baz}, response: %{pretty: :nice}}
    muse = Urania.collect([r1, r2])

    assert {:ok, [%{body: %{good: :job}}, %{body: %{pretty: :nice}}]} == Urania.run!(muse)
  end

  test "simple batched source" do
    r1 = %BatchableHttpSource { url: "google.com/foo", params: %{foo: :bar}, response: %{good: :job}}
    r2 = %BatchableHttpSource { url: "google.com/bar", params: %{bar: :hey}, response: %{pretty: :good}}
    muse = Urania.collect([r1, r2])

    assert {:ok, [%{body: %{good: :job, batched: true}},
                  %{body: %{pretty: :good, batched: true}}]} == Urania.run!(muse)
  end
end
