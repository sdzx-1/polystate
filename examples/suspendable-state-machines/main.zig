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
