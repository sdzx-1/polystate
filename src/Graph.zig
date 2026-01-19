const std = @import("std");
const ps = @import("polystate.zig");
const Mode = ps.Mode;
const Method = ps.Method;
const Adler32 = std.hash.Adler32;

arena: std.heap.ArenaAllocator,
name: []const u8,
nodes: std.ArrayListUnmanaged(Node),
edges: std.ArrayListUnmanaged(Edge),

const Graph = @This();

pub const Node = struct {
    name: []const u8,
    id: u32,
    fsm_name: []const u8,
};

pub const Edge = struct {
    from: u32,
    to: u32,
    color: Color,
    label: []const u8,
};

pub const Color = enum {
    black,
    blue,
};

pub const Save = struct {
    name: []const u8,
    nodes: []const Node,
    edges: []const Edge,
};

pub fn generateJson(self: @This(), writer: anytype) !void {
    const save: Save = .{
        .name = self.name,
        .nodes = self.nodes.items,
        .edges = self.edges.items,
    };

    try std.json.stringify(save, .{ .whitespace = .indent_2 }, writer);
}

pub fn generateDot(
    self: @This(),
    writer: anytype,
) !void {
    try writer.writeAll(
        \\digraph fsm_state_graph {
        \\
    );

    { //state graph
        try writer.writeAll(
            \\  subgraph cluster_transitions {
            \\    label = "State Transitions";
            \\    labelloc = "t";
            \\    labeljust = "c";
            \\
        );

        // Create subgraphs for each FSM's nodes
        var cluster_idx: u32 = 0;
        var current_fsm_name: ?[]const u8 = null;

        for (self.nodes.items) |node| {
            // Start new FSM subgraph if needed
            if (current_fsm_name == null or !std.mem.eql(u8, current_fsm_name.?, node.fsm_name)) {
                // Close previous subgraph if any
                if (current_fsm_name != null) {
                    try writer.writeAll(
                        \\    }
                        \\
                    );
                    cluster_idx += 1;
                }

                // Start new subgraph
                current_fsm_name = node.fsm_name;
                try writer.print(
                    \\    subgraph cluster_fsm_{d} {{
                    \\      label = "{s}";
                    \\
                , .{ cluster_idx, node.fsm_name });
            }

            // Add node to current FSM subgraph
            try writer.print(
                \\      {d} [label = "[{d}] {s}"];
                \\
            , .{ node.id, node.id, node.name });
        }

        // Close last subgraph
        if (current_fsm_name != null) {
            try writer.writeAll(
                \\    }
                \\
            );
        }

        // Add edges
        for (self.edges.items) |edge| {
            try writer.print(
                \\    {d} -> {d} [label = "{s}"{s}];
                \\
            , .{
                edge.from,
                edge.to,
                edge.label,
                switch (edge.color) {
                    .black => "",
                    .blue =>
                    \\ color = "blue"
                    ,
                },
            });
        }

        try writer.writeAll(
            \\  }
            \\
        );
    }

    try writer.writeAll(
        \\}
        \\
    );
}

pub fn generateMermaid(
    self: @This(),
    writer: anytype,
) !void {
    try writer.writeAll(
        \\---
        \\config:
        \\  layout: elk
        \\  elk:
        \\    mergeEdges: false
        \\    nodePlacementStrategy: LINEAR_SEGMENTS
        \\  theme: 'base'
        \\  themeVariables:
        \\    primaryColor: 'white'
        \\    primaryTextColor: 'black'
        \\    primaryBorderColor: 'black'
        \\  flowchart:
        \\    padding: 32
        \\---
        \\flowchart TB
        \\
    );

    // State transitions subgraph
    {
        try writer.writeAll(
            \\  subgraph transitions["State Transitions"]
            \\    linkStyle default stroke-width:2px
            \\
        );

        // Create subgraphs for each FSM's nodes
        var fsm_idx: u32 = 0;
        var current_fsm_name: ?[]const u8 = null;

        for (self.nodes.items) |node| {
            // Start new FSM subgraph if needed
            if (current_fsm_name == null or !std.mem.eql(u8, current_fsm_name.?, node.fsm_name)) {
                // Close previous subgraph if any
                if (current_fsm_name != null) {
                    try writer.writeAll(
                        \\    end
                        \\
                    );
                    fsm_idx += 1;
                }

                // Start new subgraph
                current_fsm_name = node.fsm_name;
                try writer.print(
                    \\    subgraph fsm_{d}["{s}"]
                    \\
                , .{ fsm_idx, node.fsm_name });
            }

            // Add node to current FSM subgraph
            try writer.print(
                \\      {d}(({s}))
                \\
            , .{ node.id, node.name });
        }

        // Close last subgraph
        if (current_fsm_name != null) {
            try writer.writeAll(
                \\    end
                \\
            );
        }

        // Add edges
        for (self.edges.items) |edge| {
            try writer.print(
                \\    {d} -- "{s}" --> {d}
                \\
            , .{ edge.from, edge.label, edge.to });
        }

        var blue_count: usize = 0;
        for (self.edges.items) |edge| {
            if (edge.color == .blue) {
                blue_count += 1;
            }
        }

        if (blue_count > 0) {
            try writer.writeAll(
                \\    linkStyle 
            );

            for (self.edges.items, 0..) |edge, i| {
                if (edge.color == .blue) {
                    try writer.print(
                        \\{d}{s}
                    , .{
                        i,
                        if (blue_count > 1) "," else "",
                    });

                    blue_count -= 1;
                }
            }

            try writer.writeAll(
                \\ stroke:blue
                \\
            );
        }

        try writer.writeAll(
            \\  end
            \\
        );
    }
}

pub fn initWithFsm(allocator: std.mem.Allocator, comptime FsmState: type) !Graph {
    @setEvalBranchQuota(2000000);

    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();

    const arena_allocator = arena.allocator();

    var nodes: std.ArrayListUnmanaged(Node) = .empty;
    var edges: std.ArrayListUnmanaged(Edge) = .empty;

    const state_map: ps.StateMap = comptime .init(FsmState);

    inline for (state_map.states, state_map.state_machine_names, 0..) |State, fsm_name, state_idx| {
        try nodes.append(arena_allocator, .{
            .name = State.info.name,
            .id = @intCast(state_idx),
            .fsm_name = fsm_name,
        });

        switch (@typeInfo(State)) {
            .@"union" => |un| {
                inline for (un.fields) |field| {
                    const NextData = field.type;
                    const NextState = NextData.State;

                    const next_state_idx: u32 = @intFromEnum(state_map.idFromState(NextState));

                    try edges.append(arena_allocator, .{
                        .from = @intCast(state_idx),
                        .to = next_state_idx,
                        .color = switch (NextData.method) {
                            .current => .black,
                            .next => .blue,
                        },
                        .label = field.name,
                    });
                }
            },
            else => @compileError("Only support tagged union!"),
        }
    }

    // Sort nodes by FSM name
    std.mem.sort(Node, nodes.items, {}, struct {
        pub fn lessThan(_: void, lhs: Node, rhs: Node) bool {
            const cmp = std.mem.order(u8, lhs.fsm_name, rhs.fsm_name);
            if (cmp != .eq) return cmp == .lt;
            return lhs.id < rhs.id;
        }
    }.lessThan);

    return .{
        .arena = arena,
        .edges = edges,
        .name = @TypeOf(FsmState.info).StateMachineName,
        .nodes = nodes,
    };
}

pub fn deinit(self: *Graph) void {
    self.arena.deinit();
}
