defmodule Ngauge.Worker.Chain do
  @moduledoc """
  Retrieves a certificate chain from host (by name or IP)

  Fake for now
  """
  alias Ngauge.Queue

  @spec run(binary) :: [binary]
  def run(arg) do
    # special arguments with special (re)actions
    # donot forget to have the catch all clause at the end
    case arg do
      "1.1.1.0" -> raise "boom"
      "1.1.1.1" -> Process.sleep(10_000)
      "1.1.1.2" -> Queue.enq(__MODULE__, ["badaboom!", "2.2.2.0/31"])
      "1.1.1.3" -> matherr(0)
      "1.1.1.4" -> Queue.enq(Ngauge.Worker.Ping, [arg])
      _ -> nil
    end

    :rand.uniform(500) |> Process.sleep()

    ["cert1", "cert2", "cert3"] |> Enum.take(:rand.uniform(3))
  end

  def format(result) do
    case result do
      x when is_exception(x) -> Exception.message(x)
      x -> "#{inspect(x)}"
    end
  end

  @spec to_str([any]) :: binary
  def to_str(result) do
    "saw #{Enum.count(result)} certs -- " <> Enum.join(result, ", ")
  end

  @spec to_csv([any]) :: [binary]
  def to_csv(result) do
    result
    |> Enum.with_index(fn elm, idx -> "#{idx},#{elm}" end)
  end

  defp matherr(n), do: 1 / n
end
