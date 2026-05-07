# Polystate

**Build type-safe finite state machines with higher-order states.**

With Polystate, you can write 'state functions' that produce entirely new states, whose transitions are decided by a set of parameters. This enables composition: constructing states using other states, or even other state functions.

## Adding Polystate to your project

Download and add Polystate as a dependency by running the following command in your project root:
```shell
zig fetch --save git+https://github.com/sdzx-1/polystate.git
```

Then, retrieve the dependency in your build.zig:
```zig
const polystate = b.dependency("polystate", .{
    .target = target,
    .optimize = optimize,
});
```

Finally, add the dependency's module to your module's imports:
```zig
exe_mod.addImport("polystate", polystate.module("root"));
```

You should now be able to import Polystate in your module's code:
```zig
const ps = @import("polystate");
```

## The basics

Let's build a state machine that completes a simple task: capitalize all words in a string that contain an underscore.

Our state machine will contain three states: `FindWord`, `CheckWord`, and `Capitalize`:
- `FindWord` finds the start of a word. `FindWord` transitions to `CheckWord` if it finds the start of a word.
- `CheckWord` checks if an underscore exists in the word. `CheckWord` transitions to `Capitalize` if an underscore is found, or transitions back to `FindWord` if no underscore is found.
- `Capitalize` capitalizes the word. `Capitalize` transitions back to `FindWord` once the word is capitalized.

Here's our state machine implemented with Polystate:
<details open>
<summary><code>main.zig</code></summary>

```zig

const std = @import("std");
const ps = @import("polystate");
const Data = ps.Data;

pub const FindWord = union(enum) {
    to_check_word: Data(.current, CheckWord),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, FindWord),

    pub const info = caps_fsm_info("FindWord");

    pub fn handler(ctx: *Context) FindWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .no_transition;
            },
            else => {
                ctx.word = ctx.string;
                return .to_check_word;
            },
        }
    }
};

pub const CheckWord = union(enum) {
    to_find_word: Data(.current, FindWord),
    to_capitalize: Data(.current, Capitalize),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, CheckWord),

    pub const info = caps_fsm_info("CheckWord");

    pub fn handler(ctx: *Context) CheckWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            '_' => {
                ctx.string = ctx.word;
                return .to_capitalize;
            },
            else => {
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Capitalize = union(enum) {
    to_find_word: Data(.current, FindWord),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, Capitalize),

    pub const info = caps_fsm_info("Capialize");

    pub fn handler(ctx: *Context) Capitalize {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            else => {
                ctx.string[0] = std.ascii.toUpper(ctx.string[0]);
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Context = struct {
    string: [*:0]u8,
    word: [*:0]u8,

    pub fn init(string: [:0]u8) Context {
        return .{
            .string = string.ptr,
            .word = string.ptr,
        };
    }
};

fn caps_fsm_info(name: []const u8) ps.StateInfo("Underscore Capitalizer", Context) {
    return .{ .name = name };
}

pub const EnterFsmState = FindWord;

pub fn main() void {
    const Runner = ps.Runner(EnterFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    const starting_state_id = Runner.idFromState(EnterFsmState);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    Runner.runHandler(.not_suspendable, false, null, starting_state_id, &ctx);

    std.debug.print("With caps:\n{s}\n", .{string});
}
```

</details>

---

<details open>
<summary>Transition graph for <code>main.zig</code></summary>

![graph](./examples/getting-started/graph.svg)

</details>

---

As you can see, each of our states is represented by a tagged union. These unions have two main components: their fields and their `handler` function.

Rules for the fields:
- Each field represents one of the state's transitions.
- The type of a field describes the transition, containing the target state and a method indicating how the runner should proceed.
- Field types are created using `Data(method, State)`, where `method` is either `.current` (continue running) or `.next` (suspend after transitioning), and `State` is the target state type.
- Each state must expose a public `info` declaration created with `StateInfo("MachineName", Context)`, which ties the state to a named state machine and a shared context type.

Rules for the `handler` function:
- `handler` executes the state's logic and determines which transition to take.
- `handler` takes a context parameter (`ctx`), which points to mutable data that is shared across all states.
- `handler` returns a transition (one of the state's union fields).

Once we have defined the states of our state machine, we make a runner using `ps.Runner`, passing the entry state type directly: `ps.Runner(EnterFsmState)`. The runner will discover all reachable states from the entry state at compile time. Since we use `not_suspendable` mode, calling `runHandler` on our runner will run the state machine until completion (when the special `ps.Exit` state is reached).

`runHandler` also requires the 'state ID' of the state you want to start at. A runner provides both the `StateId` type and functions to convert between states and their ID. We use this to get the starting state ID: `Runner.idFromState(EnterFsmState)`.

There is no wrapping layer around `EnterFsmState` — it is simply the state type itself (in this case `FindWord`). The runner uses compile-time reflection to traverse all reachable states from this starting point.

## Suspendable state machines
In our previous example, our state machine's mode was `not_suspendable`. What if we set it to `suspendable`? Well, this would allow us to 'suspend' the execution of our state machine, run code outside of the state machine, and then resume the execution of our state machine.

However, `suspendable` adds an additional requirement to your state transitions: they must tell the state machine whether or not to suspend after transitioning.

This is our capitalization state machine, updated such that every time a word is chosen to be capitalized, we suspend execution and print the chosen word:


<details>
<summary><code>main.zig</code></summary>

```zig
const std = @import("std");
const ps = @import("polystate");
const Data = ps.Data;

pub const FindWord = union(enum) {
    to_check_word: Data(.current, CheckWord),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, FindWord),

    pub const info = caps_fsm_info("FindWord");

    pub fn handler(ctx: *Context) FindWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .no_transition;
            },
            else => {
                ctx.word = ctx.string;
                return .to_check_word;
            },
        }
    }
};

pub const CheckWord = union(enum) {
    to_find_word: Data(.current, FindWord),
    to_capitalize: Data(.next, Capitalize),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, CheckWord),

    pub const info = caps_fsm_info("CheckWord");

    pub fn handler(ctx: *Context) CheckWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            '_' => {
                ctx.string = ctx.word;
                return .to_capitalize;
            },
            else => {
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Capitalize = union(enum) {
    to_find_word: Data(.current, FindWord),
    exit: Data(.current, ps.Exit),
    no_transition: Data(.current, Capitalize),

    pub const info = caps_fsm_info("Capialize");

    pub fn handler(ctx: *Context) Capitalize {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            else => {
                ctx.string[0] = std.ascii.toUpper(ctx.string[0]);
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Context = struct {
    string: [*:0]u8,
    word: [*:0]u8,

    pub fn init(string: [:0]u8) Context {
        return .{
            .string = string.ptr,
            .word = string.ptr,
        };
    }
};

fn caps_fsm_info(name: []const u8) ps.StateInfo("Underscore Capitalizer", Context) {
    return .{ .name = name };
}

pub const EnterFsmState = FindWord;

pub fn main() void {
    const Runner = ps.Runner(EnterFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    var state_id = Runner.idFromState(EnterFsmState);

    while (Runner.runHandler(.suspendable, false, null, state_id, &ctx)) |new_state_id| {
        state_id = new_state_id;

        var word_len: usize = 0;
        while (ctx.word[word_len] != 0 and !std.ascii.isWhitespace(ctx.word[word_len])) {
            word_len += 1;
        }

        const word = ctx.word[0..word_len];

        std.debug.print("capitalizing word: {s}\n", .{word});
    }

    std.debug.print("\nWith caps:\n{s}\n", .{string});
}
```

</details>

---

<details>
<summary>Transition graph for <code>main.zig</code></summary>

![graph](./examples/suspendable-state-machines/graph.svg)

</details>

---

We've updated our transitions to use `ps.Method` in their `Data` wrapper, which has two possible values: `current` and `next`.

- If a transition has the method `current`, the state machine will continue execution after transitioning.
- If a transition has the method `next`, the state machine will suspend execution after transitioning.

A transition's `ps.Method` basically answers the following question: "Should I set this new state as my current state and keep going (`current`), or save this new state for the next execution (`next`)?".

In addition to updating our state transitions with `current` or `next`, we also need to change how we use `runHandler`.

Before, since our state machine was `not_suspendable`, `runHandler` didn't return anything and only needed to be called once. Now, since our state machine is `suspendable`, `runHandler` only runs the state machine until it is suspended, and returns the ID of the state it was suspended on.

So, we now call `runHandler` in a loop, passing in the current state ID and using the result as the new state ID. We continue this until `runHandler` returns `null`, indicating that the state machine has completed (reached ps.Exit).

## Higher-order states and composability
If you've read the previous sections where we cover the basics of Polystate, you may feel like it's a bit overkill to use a library instead of just implementing your FSM manually. After all, it can seem like Polystate does little more than provide a convenient framework for structuring state machines.

This changes when you start using higher-order states.

A higher-order state is a function that takes states as parameters and returns a new state, AKA a 'state function'. Since states are represented as types (specifically, tagged unions), a state function is no different than any other Zig generic: a type-returning function that takes types as parameters.

---

While being simple at their core, higher-order states allow endless ways to construct, compose, and re-use transition logic among your states. We will demonstrate this by expanding on our previous state machine, making it perform various new word-processing operations.

Our capitalization state machine was designed with one purpose: capitalize words with underscores. Sure you could tweak it, splicing in new states to add additional processing steps... only for it to decline into a spaghetti-like mess, becoming less decipherable with each new state. If we want to make our state machine truly extendable, we'll need to try another approach.

Let's make a new utility called `Words` that will provide us with several state functions, producing states that operate on a `WordsContext`. These state functions will allow us to construct word operations, expressing in a consistent manner both the word mutations and the conditions in which those mutations occur. 

As a bonus, `Words` itself will be produced by a generic function, automatically specializing its state functions based on its parameters. This allows `Words` to be used in any state machine, and even lets you create multiple independent instances of `Words` in one state machine, each one having its own `WordsContext`!

Our new state machine will demonstrate the capabilities of `Words`, using two independent instances of `Words` to do the following:
1. Capitalize all words in string 1 that contain an underscore or are palindromes.
2. Reverse all words in string 2 that contain a vowel.

Here's the implementation:

<details>
<summary><code>main.zig</code></summary>

```zig

const std = @import("std");
const ps = @import("polystate");
const Data = ps.Data;

fn word_processor_info(name: []const u8) ps.StateInfo("Word Processor", Context) {
    return .{ .name = name };
}

pub fn Words(
    comptime ParentContext: type,
    comptime ctx_field: std.meta.FieldEnum(ParentContext),
) type {
    return struct {
        pub fn IterateWords(
            comptime WordOperation: fn (Next: type) type,
            comptime NoWordsLeft: type,
        ) type {
            return union(enum) {
                to_inner: Data(.current, IterateWordsInner(WordOperation(@This()), NoWordsLeft)),

                pub const info = word_processor_info("IterateWords");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_end;
                    return .to_inner;
                }
            };
        }

        pub fn IterateWordsInner(
            comptime FoundWord: type,
            comptime NoWordsLeft: type,
        ) type {
            return union(enum) {
                to_find_word: Data(.current, FindWord(FoundWord)),
                to_no_words_left: Data(.current, NoWordsLeft),

                pub const info = word_processor_info("IterateWordsInner");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.word_end >= ctx.string.len) {
                        return .to_no_words_left;
                    } else {
                        return .to_find_word;
                    }
                }
            };
        }

        pub fn FindWord(comptime Next: type) type {
            return union(enum) {
                to_find_word_end: Data(.current, FindWordEnd(Next)),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("FindWord");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.string.len) {
                        ctx.word_start = ctx.head;
                        ctx.word_end = ctx.head;
                        return .to_find_word_end;
                    }
                    switch (ctx.string[ctx.head]) {
                        ' ', '\t'...'\r' => {
                            ctx.head += 1;
                            return .no_transition;
                        },
                        else => {
                            ctx.word_start = ctx.head;
                            ctx.word_end = ctx.head;
                            return .to_find_word_end;
                        },
                    }
                }
            };
        }

        pub fn FindWordEnd(comptime Next: type) type {
            return union(enum) {
                to_next: Data(.current, Next),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("FindWordEnd");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.word_end >= ctx.string.len) {
                        return .to_next;
                    }
                    switch (ctx.string[ctx.word_end]) {
                        ' ', '\t'...'\r' => return .to_next,
                        else => {
                            ctx.word_end += 1;
                            return .no_transition;
                        },
                    }
                }
            };
        }

        pub fn CharMutation(
            comptime Next: type,
            mutateChar: fn (char: u8) u8,
        ) type {
            return union(enum) {
                to_inner: Data(.current, CharMutationInner(Next, mutateChar)),

                pub const info = word_processor_info("CharMutation");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_start;
                    return .to_inner;
                }
            };
        }

        pub fn CharMutationInner(
            comptime Next: type,
            mutateChar: fn (char: u8) u8,
        ) type {
            return union(enum) {
                to_next: Data(.current, Next),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("CharMutationInner");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.word_end) {
                        return .to_next;
                    } else {
                        ctx.string[ctx.head] = mutateChar(ctx.string[ctx.head]);
                        ctx.head += 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn Reverse(comptime Next: type) type {
            return union(enum) {
                to_inner: Data(.current, ReverseInner(Next)),

                pub const info = word_processor_info("Reverse");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.tail = ctx.word_start;
                    ctx.head = ctx.word_end - 1;
                    return .to_inner;
                }
            };
        }

        pub fn ReverseInner(comptime Next: type) type {
            return union(enum) {
                to_next: Data(.current, Next),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("ReverseInner");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.tail >= ctx.head) {
                        return .to_next;
                    } else {
                        const temp = ctx.string[ctx.tail];
                        ctx.string[ctx.tail] = ctx.string[ctx.head];
                        ctx.string[ctx.head] = temp;
                        ctx.tail += 1;
                        ctx.head -= 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn CharFilter(
            comptime Pass: type,
            comptime Fail: type,
            comptime predicate: fn (char: u8) bool,
        ) type {
            return union(enum) {
                to_inner: Data(.current, CharFilterInner(Pass, Fail, predicate)),

                pub const info = word_processor_info("CharFilter");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_start;
                    return .to_inner;
                }
            };
        }

        pub fn CharFilterInner(
            comptime Pass: type,
            comptime Fail: type,
            comptime predicate: fn (char: u8) bool,
        ) type {
            return union(enum) {
                to_pass: Data(.current, Pass),
                to_fail: Data(.current, Fail),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("CharFilterInner");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.word_end) {
                        return .to_fail;
                    }
                    if (predicate(ctx.string[ctx.head])) {
                        return .to_pass;
                    } else {
                        ctx.head += 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn PalindromeFilter(
            comptime Pass: type,
            comptime Fail: type,
        ) type {
            return union(enum) {
                to_inner: Data(.current, PalindromeFilterInner(Pass, Fail)),

                pub const info = word_processor_info("PalindromeFilter");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.tail = ctx.word_start;
                    ctx.head = ctx.word_end - 1;
                    return .to_inner;
                }
            };
        }

        pub fn PalindromeFilterInner(
            comptime Pass: type,
            comptime Fail: type,
        ) type {
            return union(enum) {
                to_pass: Data(.current, Pass),
                to_fail: Data(.current, Fail),
                no_transition: Data(.current, @This()),

                pub const info = word_processor_info("PalindromeFilterInner");

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.tail >= ctx.head) {
                        return .to_pass;
                    } else if (ctx.string[ctx.tail] != ctx.string[ctx.head]) {
                        return .to_fail;
                    } else {
                        ctx.tail += 1;
                        ctx.head -= 1;
                        return .no_transition;
                    }
                }
            };
        }

        fn ctxFromParent(parent_ctx: *ParentContext) *WordsContext {
            return &@field(parent_ctx, @tagName(ctx_field));
        }
    };
}

pub const WordsContext = struct {
    string: []u8,
    head: usize,
    word_start: usize,
    word_end: usize,
    tail: usize,

    pub fn init(string: []u8) WordsContext {
        return .{
            .string = string,
            .head = 0,
            .word_start = 0,
            .word_end = 0,
            .tail = 0,
        };
    }
};

pub const Context = struct {
    string1_ctx: WordsContext,
    string2_ctx: WordsContext,

    pub fn init(string1: []u8, string2: []u8) Context {
        return .{
            .string1_ctx = .init(string1),
            .string2_ctx = .init(string2),
        };
    }
};

const string1_states = struct {
    const W = Words(Context, .string1_ctx);

    fn isUnderscore(char: u8) bool {
        return char == '_';
    }

    fn capitalize(char: u8) u8 {
        return std.ascii.toUpper(char);
    }

    pub fn UnderscoreFilter(comptime Pass: type, comptime Fail: type) type {
        return W.CharFilter(Pass, Fail, isUnderscore);
    }

    pub fn Capitalize(comptime Next: type) type {
        return W.CharMutation(Next, capitalize);
    }

    pub fn UnderscoreOrPalindromeFilter(comptime Pass: type, comptime Fail: type) type {
        return UnderscoreFilter(
            Pass,
            W.PalindromeFilter(Pass, Fail),
        );
    }

    pub fn CapitalizeUnderscoreOrPalindromeWord(comptime Next: type) type {
        return UnderscoreOrPalindromeFilter(
            Capitalize(Next),
            Next,
        );
    }

    pub fn CapitalizeUnderscoreOrPalindromeWords(comptime Next: type) type {
        return W.IterateWords(
            CapitalizeUnderscoreOrPalindromeWord,
            Next,
        );
    }
};

const string2_states = struct {
    const W = Words(Context, .string2_ctx);

    fn isVowel(char: u8) bool {
        return switch (char) {
            'a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U' => true,
            else => false,
        };
    }

    pub fn VowelFilter(comptime Pass: type, comptime Fail: type) type {
        return W.CharFilter(Pass, Fail, isVowel);
    }

    pub fn ReverseWordWithVowel(comptime Next: type) type {
        return VowelFilter(
            W.Reverse(Next),
            Next,
        );
    }

    pub fn ReverseVowelWords(comptime Next: type) type {
        return W.IterateWords(
            ReverseWordWithVowel,
            Next,
        );
    }
};

pub const EnterFsmState =
    string1_states.CapitalizeUnderscoreOrPalindromeWords(
        string2_states.ReverseVowelWords(ps.Exit),
    );

pub fn main() !void {
    const Runner = ps.Runner(EnterFsmState);

    var string1_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
        \\tacocat 123Hello--olleH321
    .*;

    var string2_backing =
        \\apple gym cry
        \\elephant pfft sphinx
        \\amazing fly grr
    .*;

    var ctx: Context = .init(&string1_backing, &string2_backing);

    const starting_state_id = Runner.idFromState(EnterFsmState);

    std.debug.print("Before processing:\n", .{});
    std.debug.print("String 1: {s}\n", .{string1_backing});
    std.debug.print("String 2: {s}\n\n", .{string2_backing});

    Runner.runHandler(.not_suspendable, false, null, starting_state_id, &ctx);

    std.debug.print("After processing:\n", .{});
    std.debug.print("String 1: {s}\n", .{string1_backing});
    std.debug.print("String 2: {s}\n", .{string2_backing});
}
```

</details>

---

<details>
<summary>Transition graph for <code>main.zig</code></summary>

![graph](./examples/higher-order-states/graph.svg)

</details>

---

## Performance

Polystate is designed with both compilation and runtime performance in mind.

**Compilation performance.** Despite using compile-time reflection to enumerate all reachable states, a state machine with 4000 states compiles in under one minute:

```
❯ time zig build bench

________________________________________________________
Executed in   45.15 secs    fish           external
   usr time   45.92 secs  237.00 micros   45.92 secs
   sys time    1.06 secs   99.00 micros    1.06 secs
```

**Runtime performance.** Polystate compiles the state machine into Zig's `label switch` construct at compile time. Transitions between states are equivalent to `goto` jumps — no function pointer tables, no dynamic dispatch, no allocation overhead.

## Summary

Polystate is, at its core, **composable goto**. Zig's `label switch` already gives you goto-level runtime performance — unconditional jumps with no call-stack overhead. What Polystate adds is the missing piece: the ability to compose those control-flow primitives using Zig's type system, entirely at compile time.

State functions (generic functions that produce new state types) are the composability primitive. They let you build complex state machines by assembling smaller ones, just as functions let you build complex logic by composing simpler functions — but without sacrificing the raw performance of a hand-written state machine loop.
