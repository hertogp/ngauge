defmodule Ngauge.Worker.Pong do
  @moduledoc """
  A fake ping worker (for now)
  """

  def run(_arg) do
    min = :rand.uniform(100)
    max = min + :rand.uniform(50)
    avg = div(min + max, 2)
    (3_000 + :rand.uniform(1_500)) |> Process.sleep()

    {min, avg, max}
  end

  def format(result) do
    case result do
      x when is_exception(x) -> Exception.message(x) |> String.slice(0, 50)
      nil -> "nil"
      {min, avg, max} -> "min/avg/max #{min}/#{avg}/#{max} ms"
    end
  end
end
