defmodule ExparicTest.Transform do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Exparic.Transform

  describe "strip" do
    property "string" do
      check all st <- StreamData.string(:alphanumeric),
                empty_st <-  member_of([" ", "\n", "\n \n"]),
                empty_end <- member_of(["  ", "\n", "\n \n"]) do
        value = "#{empty_st}#{st}#{empty_end}"
        assert Transform.transform("strip", value) == st
      end
    end

    test "string static" do
      for {input, expected} <- [{" one ", "one"},
                                {"\n eewe ", "eewe"},
                                {"\n\n123_3\n\n", "123_3"},
                                {"  __ __ ", "__ __"}] do
        assert Transform.transform("strip", input) == expected
      end
    end

    test "list static" do
      for {input, expected} <- [
        {[" one ", " two "], ["one", "two"]},
        {["\n\n123_3\n\n", "__ __ "], ["123_3", "__ __"]}] do
        assert Transform.transform("strip", input) == expected
      end
    end
  end

  describe "int" do
    property "int" do
      check all v <- StreamData.integer() do
        assert Transform.transform("int", "#{v}") == v
      end
    end

    test "int static" do
      for {input, expected} <- [{"-31", -31},
                                {"+65", 65},
                                {"+45.5", 45},
                                {"0.003", 0}] do
        assert Transform.transform("int", input) == expected
      end
    end
  end

  test "replace static" do
    for {{params, input}, expected} <- [
      {{"q ,", "qwerty "}, "werty"},
      {{"-=0,x", "12-0c-=8"}, "12xxcxx8"},
      {{"°,", "76°"}, "76"},
      ] do
      assert Transform.transform("replace::" <> params, input) == expected
    end
  end

  test "split static" do
    for {{params, input}, expected} <- [
      {{"0", "qwerty uiop"}, "qwerty"},
      {{"1", "qwerty uiop"}, "uiop"},
      {{"0", "qwertyuiop"}, "qwertyuiop"},
      ] do
      assert Transform.transform("split::" <> params, input) == expected
    end
  end

  test "index static" do
    for {{params, input}, expected} <- [
      {{"0,2", "qwerty_uiop"}, "qwe"},
      {{"2,4", "qwerty_uiop"}, "ert"},
      {{"0,-1", "qwerty_uiop"}, "qwerty_uiop"},
      ] do
      assert Transform.transform("index::" <> params, input) == expected
    end
  end

  test "transform unknown func" do
    for {func, input} <- [{"what?", -31},
                          {"to_lower_space", 65},
                          {"kek!", 45},
                          {"to_matrix", 0}] do
      assert Transform.transform(func, input) == input
    end
  end

  describe "apply_rules" do
    test "nil value" do
      assert Transform.apply_rules(nil, ["some", "filters"]) == nil
    end

    test "nil filters" do
      assert Transform.apply_rules(42, nil) == 42
    end

    test "filters pipe" do
      for {v, filters, expected} <- [
        {"\n on-37°", ["strip", "index::2,-1", "replace::°,", "int"], -37},
        {"isbn::1234-5", ["index::6,-1", "replace::-,", "int"], 12345},
      ] do
        assert Transform.apply_rules(v, filters) == expected
      end
    end
  end
end
