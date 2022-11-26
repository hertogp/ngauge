defmodule Ngauge.Worker.Ping do
  @moduledoc """
  A fake ping worker (for now)
  """

  @name Module.split(__MODULE__) |> List.last()

  def run(_arg) do
    min = :rand.uniform(100)
    max = min + :rand.uniform(50)
    avg = div(min + max, 2)
    (1_000 + :rand.uniform(1_500)) |> Process.sleep()

    {min, avg, max}
  end

  def format(result) do
    case result do
      x when is_exception(x) -> @name <> (Exception.message(x) |> String.slice(0, 50))
      nil -> "nil"
      {min, avg, max} -> "min/avg/max #{min}/#{avg}/#{max} ms"
    end
  end
end
