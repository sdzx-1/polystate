const std = @import("std");
const builtin = @import("builtin");

pub const Graph = @import("Graph.zig");

//The Exit status is unique.
pub const Exit = union(enum) {
    pub const info: Info = .{};

    pub const Info = struct {
        name: []const u8 = "Exit",

        pub const StateMachineName = "polystate_exit";
        pub const Context = void;
    };
};

pub const Mode = enum {
    not_suspendable,
    suspendable,
};

pub const Method = enum {
    next,
    current,
};

//   Data                        StateInfo
// method, State, data     StateMachineName, Context, State name

pub fn Data(method_: Method, NewState_: type) type {
    return struct {
        pub const method = method_;
        pub const State = NewState_;
    };
}

pub fn StateInfo(
    comptime StateMachineName_: []const u8,
    comptime Context_: type,
) type {
    return struct {
        name: []const u8 = "Nameless",

        pub const StateMachineName = StateMachineName_;
        pub const Context = Context_;
    };
}

pub const StateMap = struct {
    states: []const type,
    state_machine_names: []const []const u8,
    StateId: type,

    pub fn init(comptime State: type) StateMap {
        @setEvalBranchQuota(200_000_000);

        comptime {
            const result = reachableStates(State);
            return .{
                .states = result.states,
                .state_machine_names = result.state_machine_names,
                .StateId = @Type(.{
                    .@"enum" = .{
                        .tag_type = std.math.IntFittingRange(0, result.states.len - 1),
                        .fields = inner: {
                            var fields: [result.states.len]std.builtin.Type.EnumField = undefined;

                            for (&fields, result.states, 0..) |*field, State_, state_int| {
                                field.* = .{
                                    .name = @typeName(State_),
                                    .value = state_int,
                                };
                            }

                            const fields_const = fields;
                            break :inner &fields_const;
                        },
                        .decls = &.{},
                        .is_exhaustive = true,
                    },
                }),
            };
        }
    }

    pub fn StateFromId(comptime self: StateMap, comptime state_id: self.StateId) type {
        return self.states[@intFromEnum(state_id)];
    }

    pub fn idFromState(comptime self: StateMap, comptime State: type) self.StateId {
        if (!@hasField(self.StateId, @typeName(State))) @compileError(std.fmt.comptimePrint(
            "Can't find State {s}",
            .{@typeName(State)},
        ));
        return @field(self.StateId, @typeName(State));
    }

    pub fn iterator(comptime self: StateMap) Iterator {
        return .{
            .state_map = self,
            .idx = 0,
        };
    }

    pub const Iterator = struct {
        state_map: StateMap,
        idx: usize,

        pub fn next(comptime self: *Iterator) ?type {
            if (self.idx < self.state_map.states.len) {
                defer self.idx += 1;
                return self.state_map.states[self.idx];
            }

            return null;
        }
    };
};

pub fn reachableStates(comptime State: type) struct { states: []const type, state_machine_names: []const []const u8 } {
    comptime {
        const Info = @TypeOf(State.info);
        var states: []const type = &.{State};
        var state_machine_names: []const []const u8 = &.{Info.StateMachineName};
        var states_stack: []const type = &.{State};
        var states_set: TypeSet(128) = .init;
        const ExpectedContext = Info.Context;

        states_set.insert(State);

        reachableStatesDepthFirstSearch(&states, &state_machine_names, &states_stack, &states_set, ExpectedContext);

        return .{ .states = states, .state_machine_names = state_machine_names };
    }
}

fn reachableStatesDepthFirstSearch(
    comptime states: *[]const type,
    comptime state_machine_names: *[]const []const u8,
    comptime states_stack: *[]const type,
    comptime states_set: *TypeSet(128),
    comptime ExpectedContext: type,
) void {
    @setEvalBranchQuota(20_000_000);

    comptime {
        if (states_stack.len == 0) {
            return;
        }

        const CurrentState = states_stack.*[states_stack.len - 1];
        states_stack.* = states_stack.*[0 .. states_stack.len - 1];

        switch (@typeInfo(CurrentState)) {
            .@"union" => |un| {
                for (un.fields) |field| {
                    const NextState = field.type.State;
                    const NextInfo = @TypeOf(NextState.info);

                    if (!states_set.has(NextState)) {
                        // Validate that the handler context type matches (skip for special states like Exit)
                        if (NextState != Exit) {
                            const NextContext = NextInfo.Context;
                            if (NextContext != ExpectedContext) {
                                @compileError(std.fmt.comptimePrint("Context type mismatch: State {s} has context type {s}, but expected {s}", .{
                                    @typeName(NextState),
                                    @typeName(NextContext),
                                    @typeName(ExpectedContext),
                                }));
                            }
                        }

                        states.* = states.* ++ &[_]type{NextState};
                        state_machine_names.* = state_machine_names.* ++ &[_][]const u8{NextInfo.StateMachineName};
                        states_stack.* = states_stack.* ++ &[_]type{NextState};
                        states_set.insert(NextState);

                        reachableStatesDepthFirstSearch(states, state_machine_names, states_stack, states_set, ExpectedContext);
                    }
                }
            },
            else => @compileError("Only support tagged union!"),
        }
    }
}

fn TypeSet(comptime bucket_count: usize) type {
    return struct {
        buckets: [bucket_count][]const type,

        const Self = @This();

        pub const init: Self = .{
            .buckets = @splat(&.{}),
        };

        pub fn insert(comptime self: *Self, comptime Type: type) void {
            comptime {
                const hash = std.hash_map.hashString(@typeName(Type));

                self.buckets[hash % bucket_count] = self.buckets[hash % bucket_count] ++ &[_]type{Type};
            }
        }

        pub fn has(comptime self: Self, comptime Type: type) bool {
            comptime {
                const hash = std.hash_map.hashString(@typeName(Type));

                return std.mem.indexOfScalar(type, self.buckets[hash % bucket_count], Type) != null;
            }
        }

        pub fn items(comptime self: Self) []const type {
            comptime {
                var res: []const type = &.{};

                for (&self.buckets) |bucket| {
                    res = res ++ bucket;
                }

                return res;
            }
        }
    };
}

pub fn Runner(
    comptime State: type,
) type {
    return struct {
        pub const Context = @TypeOf(State.info).Context;
        pub const state_map: StateMap = .init(State);
        pub const StateId = state_map.StateId;

        pub fn idFromState(comptime State_: type) StateId {
            return state_map.idFromState(State_);
        }

        pub fn StateFromId(comptime state_id: StateId) type {
            return state_map.StateFromId(state_id);
        }

        pub fn runHandler(
            comptime mode: Mode,
            comptime is_inline: bool,
            comptime enter_fn: ?fn (anytype, type) void,
            curr_id: StateId,
            ctx: *Context,
        ) switch (mode) {
            .suspendable => ?StateId,
            .not_suspendable => void,
        } {
            @setEvalBranchQuota(10_000_000);
            sw: switch (curr_id) {
                inline else => |state_id| {
                    if (comptime builtin.zig_version.order(.{ .major = 0, .minor = 15, .patch = 0 }) == .lt) {
                        //  https://github.com/ziglang/zig/issues/24323
                        var runtime_false = false;
                        _ = &runtime_false;
                        if (runtime_false) continue :sw @enumFromInt(0);
                    }

                    const CurrState = StateFromId(state_id);

                    if (CurrState == Exit) {
                        return switch (mode) {
                            .suspendable => null,
                            .not_suspendable => {},
                        };
                    }

                    if (enter_fn) |fun| fun(ctx, CurrState);

                    const handle_res = @call(
                        if (is_inline) .always_inline else .auto,
                        CurrState.handler,
                        .{ctx},
                    );

                    if (@hasDecl(CurrState, "prehandler")) {
                        CurrState.prehandler(ctx, handle_res);
                    }

                    switch (handle_res) {
                        inline else => |new_fsm_state_wit| {
                            const NewData = @TypeOf(new_fsm_state_wit);
                            const NewState = NewData.State;
                            const new_id = comptime idFromState(NewState);

                            switch (NewData.method) {
                                .next => return new_id,
                                .current => continue :sw new_id,
                            }
                        },
                    }
                },
            }
        }
    };
}

test "polystate suspendable" {
    const Context = struct {
        a: i32,
        b: i32,
        max_a: i32,
    };

    const Tmp = struct {
        pub fn example_info(name: []const u8) StateInfo("Example", Context) {
            return .{ .name = name };
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Data(.next, Exit),
            to_B : Data(.next, B),
            to_B1: Data(.current, B),
            // zig fmt: on

            pub const info = example_info("A");

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Data(.next, A),

            pub const info = example_info("B");

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const ExampleRunner = Runner(Tmp.A);

    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        var curr_id: ?ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        while (curr_id) |id| {
            curr_id = ExampleRunner.runHandler(.suspendable, false, null, id, &ctx);
        }

        try std.testing.expectEqual(max_a, ctx.a);
        try std.testing.expectEqual(max_a, ctx.b);
    }
}

test "polystate not_suspendable" {
    const Context = struct {
        a: i32,
        b: i32,
        max_a: i32,
    };

    const Tmp = struct {
        pub fn example_info(name: []const u8) StateInfo("Example", Context) {
            return .{ .name = name };
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Data(.current, Exit),
            to_B : Data(.current, B),
            to_B1: Data(.current, B),
            // zig fmt: on

            pub const info = example_info("A");

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Data(.current, A),

            pub const info = example_info("B");

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const ExampleRunner = Runner(Tmp.A);

    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        const curr_id: ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        ExampleRunner.runHandler(.not_suspendable, false, null, curr_id, &ctx);

        try std.testing.expectEqual(max_a, ctx.a);
        try std.testing.expectEqual(max_a, ctx.b);
    }
}
