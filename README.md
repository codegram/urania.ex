# Urania.ex

[![Travis](https://img.shields.io/travis/codegram/urania.ex.svg?style=flat-square)](https://travis-ci.org/codegram/urania.ex)
[![Hex.pm](https://img.shields.io/hexpm/v/urania.svg?style=flat-square)](https://hex.pm/packages/urania)

Efficient and elegant data access for Elixir.

    NOTE: This is an experimental library until some issues with its underlying
    execution model ([Pinky](https://github.com/codegram/pinky) promises) are fleshed out.
    However, the public API is considered mostly stable, as the execution model is
    completely separate from the semantics of constructing muses.

This is a one-to-one port of [funcool/urania](https://github.com/funcool/urania)
for Elixir.

A brief explanation blatantly stolen from [Urania for Clojure's original guide](https://funcool.github.io/urania/latest/) ensues:

    Oftentimes, your business logic relies on remote data that you need to fetch
    from different sources: databases, caches, web services, or third party APIs,
    and you can’t mess things up. Urania helps you to keep your business logic clear
    of low-level details while performing efficiently:

    * batch multiple requests to the same data source

    * request data from multiple data sources concurrently

    * cache previous requests

    Having all this gives you the ability to access remote data sources in a concise
    and consistent way, while the library handles batching and overlapping requests
    to multiple data sources behind the scenes.

## Usage

First define your own data source:

```elixir
defmodule MyHttpSource do
  defstruct [:url, :params]
end

defimpl Urania.DataSource, for: MyHttpSource do
  def identity(this) do
    [this.url, this.params]
  end
  
  def fetch(this, env) do
    # ... perform an actual HTTP request and return the result
  end
end
```

Now you're ready to construct muses, which are sort of like composable request
plans that will be carried out when you actually run the muses with `Urania.run!`.

```elixir
muse = [%MyHttpSource { url: "www.google.com" },
        %MyHttpSource { url: "www.something.com"}]
       |> Urania.collect # lay them out in parallel
       |> Urania.flat_map(fn ([response_from_google response_from_something]) ->
          if response_from_google[:foo] do
            %MyHttpSource { url: "www.foo.com", params: response_from_google[:foo_params] }
          else
            Urania.value(Map.put(response_from_something, :good, :job))
          end
        end)
       |> Urania.map(&validate_final_response/1)

# Whenever you actually want to run the request plan:

Urania.run!(muse)
{:ok, <response>}
```

Urania will take care of deduplicating requests and caching them within a single
run. If you implement the `BatchedSource` protocol for your data source in
addition to `DataSource`, Urania will batch all your parallel requests into a
single one by calling the `fetch_multi` function you need to satisfy:

```elixir
defimpl Urania.BatchedSource, for: MyHttpSource do
  def fetch_multi(request, more_requests, env) do
    # batch together request and more_requests into a single one.
    # this function MUST return a map from request `identity`s to responses.
  end
end
```

Make sure to check out [Urania for Clojure's original guide](https://funcool.github.io/urania/latest/) for deeper
understanding. The only difference is that `flat_map` in Urania.ex is `mapcat`
in Clojure Urania. Everything else should have the same names and semantics.

## Installation

  1. Add `urania` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:urania, "~> 0.1.0"}]
    end
    ```
## Documentation

Check out [the API documentation](https://hexdocs.pm/urania/Urania) for detailed
examples of each of the Urania primitives.

## Acknowledgements

Urania for Clojure is an awesome project: kudos to [its authors and maintainers](https://github.com/funcool/urania/graphs/contributors).
