defmodule Expression.Eval do
  @moduledoc """
  Expression.Eval is responsible for taking an abstract syntax
  tree (AST) as generated by Expression.Parser and evaluating it.

  At a high level, an AST consists of a Keyword list with two top-level
  keys, either `:text` or `:expression`.

  `Expression.eval!/3` will return the output for each entry in the Keyword
  list. `:text` entries are returned as regular strings. `:expression` entries
  are returned as typed values.

  The returned value is a list containing each.

  # Example

    iex(1)> Expression.Eval.eval!([text: "hello"], %{})
    ["hello"]
    iex(2)> Expression.Eval.eval!([text: "hello", expression: [literal: 1]], %{})
    ["hello", 1]
    iex(3)> Expression.Eval.eval!([
    ...(3)>   text: "hello",
    ...(3)>   expression: [literal: 1],
    ...(3)>   text: "ok",
    ...(3)>   expression: [literal: true]
    ...(3)> ], %{})
    ["hello", 1, "ok", true]

  """
  def eval!(ast, context, mod \\ Expression.Callbacks)

  def eval!({:expression, [ast]}, context, mod) do
    eval!(ast, context, mod)
  end

  def eval!({:atom, atom}, context, _mod) do
    get_in(context, [atom])
  end

  def eval!({:attribute, [{:atom, subject}, {:atom, key}]}, context, _mod) do
    get_in(context, [subject, key]) || "@#{subject}.#{key}"
  end

  def eval!({:attribute, [subject_ast, {:atom, key}]}, context, mod) do
    subject = eval!(subject_ast, context, mod)
    get_in(subject, [key])
  end

  def eval!({:function, opts}, context, mod) do
    name = opts[:name] || raise "Functions need a name"
    arguments = opts[:args] || []

    evaluated_arguments =
      arguments
      |> Enum.reduce([], &[eval!(&1, context, mod) | &2])
      |> Enum.reverse()

    case mod.handle(name, evaluated_arguments, context) do
      {:ok, value} -> value
      {:error, reason} -> "ERROR: #{inspect(reason)}"
    end
  end

  def eval!({:lambda, [{:args, ast}]}, context, mod) do
    fn arguments ->
      lambda_context = Map.put(context, "__captures", arguments)

      [result] = eval!(ast, lambda_context, mod)
      result
    end
  end

  def eval!({:capture, index}, context, _mod) do
    Enum.at(Map.get(context, "__captures"), index - 1)
  end

  def eval!({:range, [first, last]}, _context, _mod),
    do: Range.new(first, last)

  def eval!({:range, [first, last, step]}, _context, _mod),
    do: Range.new(first, last, step)

  def eval!({:list, [{:args, ast}]}, context, mod) do
    ast
    |> Enum.reduce([], &[eval!(&1, context, mod) | &2])
    |> Enum.reverse()
  end

  def eval!({:access, [subject_ast, key_ast]}, context, mod) do
    subject = eval!(subject_ast, context, mod)
    key = eval!(key_ast, context, mod)

    case key do
      index when is_number(index) -> get_in(subject, [Access.at(index)])
      range when is_struct(range, Range) -> Enum.slice(subject, range)
    end
  end

  def eval!({:literal, literal}, _context, _mod), do: literal
  def eval!({:text, text}, _context, _mod), do: text
  def eval!({:+, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) + eval!(b, ctx, mod, :num)
  def eval!({:-, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) - eval!(b, ctx, mod, :num)
  def eval!({:*, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) * eval!(b, ctx, mod, :num)
  def eval!({:/, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) / eval!(b, ctx, mod, :num)
  def eval!({:>, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) > eval!(b, ctx, mod, :num)
  def eval!({:>=, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) >= eval!(b, ctx, mod, :num)
  def eval!({:<, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) < eval!(b, ctx, mod, :num)
  def eval!({:<=, [a, b]}, ctx, mod), do: eval!(a, ctx, mod, :num) <= eval!(b, ctx, mod, :num)
  def eval!({:==, [a, b]}, ctx, mod), do: eval!(a, ctx, mod) == eval!(b, ctx, mod)
  def eval!({:!=, [a, b]}, ctx, mod), do: eval!(a, ctx, mod) != eval!(b, ctx, mod)
  def eval!({:^, [a, b]}, ctx, mod), do: :math.pow(eval!(a, ctx, mod), eval!(b, ctx, mod))
  def eval!({:&, [a, b]}, ctx, mod), do: [a, b] |> Enum.map_join("", &eval!(&1, ctx, mod))

  def eval!(ast, context, mod) do
    ast
    |> Enum.reduce([], fn ast, acc -> [eval!(ast, context, mod) | acc] end)
    |> Enum.reverse()
    |> Enum.map(&default_value/1)
  end

  def as_string!(ast, context, mod \\ Expression.Callbacks) do
    eval!(ast, context, mod)
    |> Enum.map_join(&Kernel.to_string/1)
  end

  defp eval!(ast, ctx, mod, type), do: ast |> eval!(ctx, mod) |> guard_type!(type)

  defp guard_type!(v, :num) when is_number(v) or is_struct(v, Decimal), do: v
  defp guard_type!(v, :num), do: raise("expression is not a number: `#{inspect(v)}`")

  defp default_value(%{"__value__" => default_value}), do: default_value
  defp default_value(value), do: value
end
