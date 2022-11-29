defmodule Ngauge.Worker.Ping do
  @moduledoc """
  A fake ping worker (for now)
  """

  @name Module.split(__MODULE__) |> List.last()

  def run(arg) do
    min = :rand.uniform(100)
    max = min + :rand.uniform(50)
    avg = div(min + max, 2)

    # Chain will enqueue 1.1.1.4 for Ping, we raise immediately
    if arg == "1.1.1.4",
      do: raise("ping 1.1.1.4 is forbidden")

    Pfx.new(arg)

    # take some time
    (1_000 + :rand.uniform(1_500)) |> Process.sleep()

    {min, avg, max}
  end

  def format(result) do
    case result do
      {min, avg, max} -> "min/avg/max #{min}/#{avg}/#{max} ms"
      x -> "** #{inspect(x)}"
    end
  end
end
