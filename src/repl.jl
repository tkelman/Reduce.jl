#   This file is part of Reduce.jl. It is licensed under the MIT license
#   Copyright (C) 2017 Michael Reed

import Base: LineEdit, REPL, REPLCompletions

ans = nothing

"""
	finished(s)

Examine the buffer in the repl to see if the input is complete
"""
function finished(s)
  str = Compat.String(LineEdit.buffer(s))
  if length(str) == 0
    return false
  elseif str[end] == ';' || str[end] == '$'
    return true
  else
    return false
  end
end

"""
	respond(repl, main)

Something dark and magic
"""
function respond(repl, main)
  (s, buf, ok) -> begin
    if !ok; return REPL.transition(s, :abort); end
    input = String(take!(buf))
    if '%' in input
      tail = last(input)                              # chop the tail
      input = subst("$(ans)", "%", input[1:end-1])    # substitute
      input = string(input, tail); end                # add the tail
    if !isempty(strip(input))
      try; global ans = RExpr(input[1:end-1]) |> rcall; REPL.reset(repl)
        if input[end] == ';'
          REPL.print_response(repl, ans, nothing, true, Base.have_color)
        else; REPL.print_response(repl, nothing, nothing, true, Base.have_color); end
      catch err; REPL.reset(repl)
        REPL.print_response(repl, err, catch_backtrace(), true, Base.have_color); end
    end
    REPL.prepare_next(repl); REPL.reset_state(s)
    s.current_mode.sticky || REPL.transition(s, main); end; end

"""
	ReduceCompletionProvider

Basic completion provider, just latex completions
"""
type ReduceCompletionProvider <: LineEdit.CompletionProvider
  r::REPL.LineEditREPL; end

function LineEdit.complete_line(c::ReduceCompletionProvider, s)
  buf = s.input_buffer; partial = Compat.String(buf.data[1:buf.ptr-1])
  full = LineEdit.input_string(s) # complete latex
  ret, range, should_complete = REPLCompletions.bslash_completions(full, endof(partial))[2]
  if length(ret) > 0 && should_complete
    return ret, partial[range], true; end
  return Compat.String[], 0:-1, false; end

function create_reduce_repl(repl, main)
  reduce_mode = LineEdit.Prompt("reduce> ";
    prompt_prefix = Base.text_colors[:blue],
    prompt_suffix = main.prompt_suffix,
    on_enter = finished,
    on_done = respond(repl, main),
    sticky = true)
  hp = main.hist; hp.mode_mapping[:reduce] = reduce_mode
  reduce_mode.hist = hp; reduce_mode.complete = ReduceCompletionProvider(repl)
  search_prompt, skeymap = LineEdit.setup_search_keymap(hp)
  prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, reduce_mode)
  mk = REPL.mode_keymap(main)
  b = Dict{Any,Any}[
    skeymap, mk, prefix_keymap, LineEdit.history_keymap,
    LineEdit.default_keymap, LineEdit.escape_defaults]
  reduce_mode.keymap_dict = LineEdit.keymap(b); reduce_mode; end

function repl_init(repl)
  rirepl = isdefined(repl, :ri) ? repl.ri : repl
  main_mode = rirepl.interface.modes[1]
  reduce_mode = create_reduce_repl(rirepl, main_mode)
  push!(rirepl.interface.modes, reduce_mode)
  const reduce_prompt_keymap = Dict{Any,Any}(
    '}' => function (s,args...)
    if isempty(s) || position(LineEdit.buffer(s)) == 0
      buf = copy(LineEdit.buffer(s))
      LineEdit.transition(s, reduce_mode) do
        LineEdit.state(s, reduce_mode).input_buffer = buf; end
    else; LineEdit.edit_insert(s, '}'); end; end)
  main_mode.keymap_dict = LineEdit.keymap_merge(
    main_mode.keymap_dict, reduce_prompt_keymap);
  nothing; end
