const std = @import("std");
const builtin = @import("builtin");

pub const Graph = @import("Graph.zig");

pub const Exit = union(enum) {};

// FSM       : fn (type) type , Example
// State     : type           , A, B
// FsmState  : type           , Example(A), Example(B)

pub const Mode = enum {
    not_suspendable,
    suspendable,
};

pub const Method = enum {
    next,
    current,
};

pub fn FSM(
    comptime name_: []const u8,
    comptime mode_: Mode,
    comptime enter_fn_: ?fn (anytype, type) void, // enter_fn args type is State, context type is derived from handler
    comptime transition_method_: if (mode_ == .not_suspendable) void else Method,
    comptime State_: type,
) type {
    return struct {
        pub const name = name_;
        pub const mode = mode_;
        pub const enter_fn = enter_fn_;
        pub const transition_method: Method = if (mode_ == .not_suspendable) .current else transition_method_;
        pub const State = State_;
    };
}

pub const StateMap = struct {
    states: []const type,
    state_machine_names: []const []const u8,
    StateId: type,

    pub fn init(comptime FsmState: type) StateMap {
        @setEvalBranchQuota(200_000_000);

        comptime {
            const result = reachableStates(FsmState);
            return .{
                .states = result.states,
                .state_machine_names = result.state_machine_names,
                .StateId = @Type(.{
                    .@"enum" = .{
                        .tag_type = std.math.IntFittingRange(0, result.states.len - 1),
                        .fields = inner: {
                            var fields: [result.states.len]std.builtin.Type.EnumField = undefined;

                            for (&fields, result.states, 0..) |*field, State, state_int| {
                                field.* = .{
                                    .name = @typeName(State),
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

pub fn Runner(
    comptime is_inline: bool,
    comptime FsmState: type,
) type {
    return struct {
        pub const Context = ContextFromState(FsmState.State);
        pub const state_map: StateMap = .init(FsmState);
        pub const StateId = state_map.StateId;
        pub const RetType =
            switch (FsmState.mode) {
                .suspendable => ?StateId,
                .not_suspendable => void,
            };

        pub fn idFromState(comptime State: type) StateId {
            return state_map.idFromState(State);
        }

        pub fn StateFromId(comptime state_id: StateId) type {
            return state_map.StateFromId(state_id);
        }

        pub fn runHandler(curr_id: StateId, ctx: *Context) RetType {
            @setEvalBranchQuota(10_000_000);
            sw: switch (curr_id) {
                inline else => |state_id| {
                    if (comptime builtin.zig_version.order(.{ .major = 0, .minor = 15, .patch = 0 }) == .lt) {
                        //  https://github.com/ziglang/zig/issues/24323
                        var runtime_false = false;
                        _ = &runtime_false;
                        if (runtime_false) continue :sw @enumFromInt(0);
                    }

                    const State = StateFromId(state_id);

                    if (State == Exit) {
                        return switch (FsmState.mode) {
                            .suspendable => null,
                            .not_suspendable => {},
                        };
                    }

                    if (FsmState.enter_fn) |fun| fun(ctx, State);

                    const handle_res = @call(
                        if (is_inline) .always_inline else .auto,
                        State.handler,
                        .{ctx},
                    );
                    switch (handle_res) {
                        inline else => |new_fsm_state_wit| {
                            const NewFsmState = @TypeOf(new_fsm_state_wit);
                            const new_id = comptime idFromState(NewFsmState.State);

                            switch (NewFsmState.transition_method) {
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

pub fn reachableStates(comptime FsmState: type) struct { states: []const type, state_machine_names: []const []const u8 } {
    comptime {
        var states: []const type = &.{FsmState.State};
        var state_machine_names: []const []const u8 = &.{FsmState.name};
        var states_stack: []const type = &.{FsmState};
        var states_set: TypeSet(128) = .init;
        const ExpectedContext = ContextFromState(FsmState.State);

        states_set.insert(FsmState.State);

        reachableStatesDepthFirstSearch(FsmState, &states, &state_machine_names, &states_stack, &states_set, ExpectedContext);

        return .{ .states = states, .state_machine_names = state_machine_names };
    }
}

fn reachableStatesDepthFirstSearch(
    comptime FsmState: type,
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

        const CurrentFsmState = states_stack.*[states_stack.len - 1];
        states_stack.* = states_stack.*[0 .. states_stack.len - 1];

        const CurrentState = CurrentFsmState.State;

        switch (@typeInfo(CurrentState)) {
            .@"union" => |un| {
                for (un.fields) |field| {
                    const NextFsmState = field.type;
                    if (CurrentFsmState.mode != NextFsmState.mode) {
                        @compileError("The Modes of the two fsm_states are inconsistent!");
                    }

                    const NextState = NextFsmState.State;

                    if (!states_set.has(NextState)) {
                        // Validate that the handler context type matches (skip for special states like Exit)
                        if (NextState != Exit) {
                            const NextContext = ContextFromState(NextState);
                            if (NextContext != ExpectedContext) {
                                @compileError(std.fmt.comptimePrint("Context type mismatch: State {s} has context type {s}, but expected {s}", .{ @typeName(NextState), @typeName(NextContext), @typeName(ExpectedContext) }));
                            }
                        }

                        states.* = states.* ++ &[_]type{NextState};
                        state_machine_names.* = state_machine_names.* ++ &[_][]const u8{NextFsmState.name};
                        states_stack.* = states_stack.* ++ &[_]type{NextFsmState};
                        states_set.insert(NextState);

                        reachableStatesDepthFirstSearch(FsmState, states, state_machine_names, states_stack, states_set, ExpectedContext);
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

fn ContextFromState(comptime State: type) type {
    if (!@hasDecl(State, "handler")) {
        @compileError("State " ++ @typeName(State) ++ " must have a handler function");
    }
    const handler_type = @TypeOf(State.handler);
    const handler_info = @typeInfo(handler_type);
    if (handler_info != .@"fn") {
        @compileError("State handler must be a function");
    }
    if (handler_info.@"fn".params.len != 1) {
        @compileError("State handler must take exactly one parameter (context)");
    }
    const param_type = handler_info.@"fn".params[0].type.?;
    const param_info = @typeInfo(param_type);
    if (param_info != .pointer) {
        @compileError("State handler parameter must be a pointer to context");
    }
    return param_info.pointer.child;
}

test "polystate suspendable" {
    const Context = struct {
        a: i32,
        b: i32,
        max_a: i32,
    };

    const Tmp = struct {
        pub fn Example(meth: Method, Current: type) type {
            return FSM("Example", .suspendable, null, meth, Current);
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Example(.next, Exit),
            to_B : Example(.next, B),
            to_B1: Example(.current, B),
            // zig fmt: on

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Example(.next, A),

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const StateA = Tmp.Example(.next, Tmp.A);

    const allocator = std.testing.allocator;
    var graph = try Graph.initWithFsm(allocator, StateA);
    defer graph.deinit();

    const ExampleRunner = Runner(true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.states.len,
    );

    // rand
    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        var curr_id: ?ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        while (curr_id) |id| {
            curr_id = ExampleRunner.runHandler(id, &ctx);
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
        pub fn Example(Current: type) type {
            return FSM("Example", .not_suspendable, null, {}, Current);
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Example(Exit),
            to_B : Example(B),
            to_B1: Example(B),
            // zig fmt: on

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Example(A),

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const StateA = Tmp.Example(Tmp.A);

    const allocator = std.testing.allocator;
    var graph = try Graph.initWithFsm(allocator, StateA);
    defer graph.deinit();

    const ExampleRunner = Runner(true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.states.len,
    );

    // rand
    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        const curr_id: ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        ExampleRunner.runHandler(curr_id, &ctx);

        try std.testing.expectEqual(max_a, ctx.a);
        try std.testing.expectEqual(max_a, ctx.b);
    }
}

test "polystate transition between state machines" {
    const Context = struct {
        value: i32,
    };

    const Tmp = struct {
        pub fn First(Current: type) type {
            return FSM("First", .not_suspendable, null, {}, Current);
        }
        
        pub fn Second(Current: type) type {
            return FSM("Second", .not_suspendable, null, {}, Current);
        }

        pub const StateA = union(enum) {
            to_b: First(StateB),
            to_c: Second(StateC),

            pub fn handler(ctx: *Context) @This() {
                if (ctx.value > 0) return .to_c;
                return .to_b;
            }
        };

        pub const StateB = union(enum) {
            exit: First(Exit),

            pub fn handler(ctx: *Context) @This() {
                ctx.value = 100;
                return .exit;
            }
        };

        pub const StateC = union(enum) {
            exit: Second(Exit),

            pub fn handler(ctx: *Context) @This() {
                ctx.value = 200;
                return .exit;
            }
        };
    };

    const StartState = Tmp.First(Tmp.StateA);

    const allocator = std.testing.allocator;
    var graph = try Graph.initWithFsm(allocator, StartState);
    defer graph.deinit();

    const ExampleRunner = Runner(true, StartState);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.states.len,
    );

    // Test going to First FSM's StateB
    {
        var ctx: Context = .{ .value = 0 };
        const curr_id: ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.StateA);
        ExampleRunner.runHandler(curr_id, &ctx);
        try std.testing.expectEqual(@as(i32, 100), ctx.value);
    }

    // Test going to Second FSM's StateC
    {
        var ctx: Context = .{ .value = 1 };
        const curr_id: ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.StateA);
        ExampleRunner.runHandler(curr_id, &ctx);
        try std.testing.expectEqual(@as(i32, 200), ctx.value);
    }
}
