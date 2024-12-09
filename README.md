## Adds `/eval` command

`/eval` takes lua code as argument and executes it. It will echo your command and show it's output and returned value.
Each player gets their own "global" environment so they can't interfere with other user's envs by accident (exposed as `cmd_eval.e[player_name]`).

## Some nice features:
### Expression/statement agnostic
This command:
```
/eval 1+2
```
Outputs this:
```
> 1+2
| 3
```

This also just works:
```
> x = 2*2
> x
| 4
```

Multiple values also work:

```
> return 1,nil,3
| 1,
| nil,
| 3
```

### Backtrace and error output
Outputs both the error and clean backtrace (stack related only to provided code)

### Print function
No need to use `core.chat_send_player()`, just use `print()` - it will do the right thing.

```
> print(here)
< (-98.0, 15.5, 33.4)
```

```
> objs = core.get_objects_inside_radius(here, 10)
> for i,o in ipairs(objs) do print(i, (o:get_luaentity() or {}).name, o:get_pos()) end
< 1 nil (-98.0, 15.5, 33.4)
< 2 mobs_animal:kitten (-101.0, 16.5, 30.0)
< 3 mobs_animal:chicken (-92.0, 15.5, 34.2)
```

### "Magic" variables
Some special variables are provided:
- `here` - position where you executed the command
- `me` - your player object
- `point` - point in the world you're pointing at with your crosshair
- `this_obj` - entity you're pointing at (can be `nil`)

### Better output for arrays and some `userdata` objects
```
> me
| #<player: "singleplayer">
```

Show indices for easier manual access:
```
> core.get_objects_inside_radius(here, 10)
| {
|  [1] = #<player: "singleplayer">,
|  [2] = #<luaentity: "mobs_animal:kitten">,
|  [3] = #<luaentity: "mobs_animal:chicken">,
| }
```

### Keeping result of last /eval in `_` variable
```
> core.get_objects_inside_radius(here, 10)
| {
|  [1] = #<player: "singleplayer">,
|  [2] = #<luaentity: "mobs_animal:kitten">,
| }
> _[2]
| #<luaentity: "mobs_animal:kitten">
> pos = _:get_pos()
> pos
| {
|  x = 123.5,
|  y = 15.0,
|  z = 68.4
| }
```

