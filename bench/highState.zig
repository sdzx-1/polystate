const std = @import("std");
const ps = @import("polystate");
const Data = ps.Data;

pub fn main() void {
    const ExampleRunner = ps.Runner(EnterState);
    var ctx: Context = .{};
    ExampleRunner.runHandler(
        .not_suspendable,
        false,
        null,
        ExampleRunner.idFromState(EnterState),
        &ctx,
    );
}

const Context = struct {};

pub fn example_info(name: []const u8) ps.StateInfo("Example", Context) {
    return .{ .name = name };
}

pub fn Dummy(comptime Next: type, comptime int: comptime_int) type {
    return union(enum) {
        to_next0: Data(.current, Next),
        to_next1: Data(.current, Next),
        to_next2: Data(.current, Next),
        to_next3: Data(.current, Next),
        to_next4: Data(.current, Next),
        to_next5: Data(.current, Next),

        pub const int_decl = int;

        pub const info = example_info(std.fmt.comptimePrint("Dummy {d}", .{int}));

        pub fn handler(_: *Context) @This() {
            return .to_next0;
        }
    };
}

pub fn Nested(comptime int: comptime_int) type {
    @setEvalBranchQuota(2000000);

    comptime {
        var State = ps.Exit;
        for (0..200) |_| {
            State = Dummy(State, int);
        }
        return State;
    }
}

pub const EnterState = union(enum) {
    to_1: Data(.current, Nested(1)),
    to_2: Data(.current, Nested(2)),
    to_3: Data(.current, Nested(3)),
    to_4: Data(.current, Nested(4)),
    to_5: Data(.current, Nested(5)),
    to_6: Data(.current, Nested(6)),
    to_7: Data(.current, Nested(7)),
    to_8: Data(.current, Nested(8)),
    to_9: Data(.current, Nested(9)),
    to_10: Data(.current, Nested(10)),
    to_11: Data(.current, Nested(11)),
    to_12: Data(.current, Nested(12)),
    to_13: Data(.current, Nested(13)),
    to_14: Data(.current, Nested(14)),
    to_15: Data(.current, Nested(15)),
    to_16: Data(.current, Nested(16)),
    to_17: Data(.current, Nested(17)),
    to_18: Data(.current, Nested(18)),
    to_19: Data(.current, Nested(19)),
    to_20: Data(.current, Nested(20)),

    pub const info = example_info("EnterState");

    pub fn handler(_: *Context) @This() {
        return .to_1;
    }
};
