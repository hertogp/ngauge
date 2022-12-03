defmodule Ngauge.Worker.Pong do
  @moduledoc """
  A fake ping worker (for now)
  """

  def run(_arg) do
    min = :rand.uniform(100)
    max = min + :rand.uniform(50)
    avg = div(min + max, 2)
    (3_000 + :rand.uniform(1_500)) |> Process.sleep()

    %{"min" => min, "avg" => avg, "max" => max}
  end

  @spec to_str(map) :: binary
  def to_str(result) do
    keys = Map.keys(result) |> Enum.join("/")
    vals = Map.values(result) |> Enum.join("/")

    "#{keys} #{vals}"
  end

  @spec to_csv(map) :: binary
  def to_csv(result) do
    "#{result["min"]},#{result["avg"]},#{result["max"]}"
  end
end
