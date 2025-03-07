defmodule App.SmppSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Registry, [keys: :unique, name: Sms.SmppRegistry]},
      {DynamicSupervisor, strategy: :one_for_one, name: Sms.SmppDynamicSupervisor},
      {Sms.SmppConfigLoader, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
