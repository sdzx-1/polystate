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
                \\      {d};
                \\
            , .{node.id});
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

    { //all_state

        try writer.writeAll(
            \\  subgraph cluster_names {
            \\    label = "State Names";
            \\    labelloc = "t";
            \\    labeljust = "c";
            \\
        );

        // Create a table for each FSM
        var table_idx: u32 = 0;
        var current_fsm_name: ?[]const u8 = null;

        for (self.nodes.items) |node| {
            // Start new FSM table if needed
            if (current_fsm_name == null or !std.mem.eql(u8, current_fsm_name.?, node.fsm_name)) {
                // Close previous table if any
                if (current_fsm_name != null) {
                    try writer.writeAll(
                        \\      </TABLE>
                        \\    >];
                        \\
                    );
                    table_idx += 1;
                }

                // Start new table
                current_fsm_name = node.fsm_name;
                try writer.print(
                    \\    table_{d} [shape=plaintext, label=<
                    \\      <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
                    \\      <TR><TD>{s}</TD></TR>
                    \\
                , .{ table_idx, node.fsm_name });
            }

            // Add node to current table
            try writer.print(
                \\      <TR><TD ALIGN="LEFT"> {d} -- {s} </TD></TR>
                \\
            , .{ node.id, node.name });
        }

        // Close last table
        if (current_fsm_name != null) {
            try writer.writeAll(
                \\      </TABLE>
                \\    >];
                \\
            );
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
                \\      {d}(({d}))
                \\
            , .{ node.id, node.id });
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

    // State names subgraph
    {
        try writer.writeAll(
            \\  subgraph names["State Names"]
            \\
        );

        // Create a table for each FSM
        var table_idx: u32 = 0;
        var current_fsm_name: ?[]const u8 = null;

        for (self.nodes.items) |node| {
            // Start new FSM table if needed
            if (current_fsm_name == null or !std.mem.eql(u8, current_fsm_name.?, node.fsm_name)) {
                // Close previous table if any
                if (current_fsm_name != null) {
                    try writer.writeAll(
                        \\    "]
                        \\
                    );
                    try writer.print(
                        \\    table_{d}@{{ shape: text }}
                        \\    table_{d}:::aligned
                        \\
                    , .{ table_idx, table_idx });
                    table_idx += 1;
                }

                // Start new table
                current_fsm_name = node.fsm_name;
                try writer.print(
                    \\    table_{d}["
                    \\      {s}<br/>
                , .{ table_idx, node.fsm_name });
            }

            // Add node to current table
            try writer.print(
                \\      {d} -- {s}<br/>
            , .{ node.id, node.name });
        }

        // Close last table
        if (current_fsm_name != null) {
            try writer.writeAll(
                \\    "]
                \\
            );
            try writer.print(
                \\    table_{d}@{{ shape: text }}
                \\    table_{d}:::aligned
                \\
            , .{ table_idx, table_idx });
        }

        try writer.writeAll(
            \\    classDef aligned text-align: left, white-space: nowrap
            \\  end
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
            .name = @typeName(State),
            .id = @intCast(state_idx),
            .fsm_name = fsm_name,
        });

        switch (@typeInfo(State)) {
            .@"union" => |un| {
                inline for (un.fields) |field| {
                    const NextFsmState = field.type;
                    const NextState = NextFsmState.State;

                    const next_state_idx: u32 = @intFromEnum(state_map.idFromState(NextState));

                    try edges.append(arena_allocator, .{
                        .from = @intCast(state_idx),
                        .to = next_state_idx,
                        .color = switch (NextFsmState.transition_method) {
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

    try deduplicateNameSubstrings(arena_allocator, &nodes);

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
        .name = FsmState.name,
        .nodes = nodes,
    };
}

// Somewhat inefficient, consider optimizing later.
fn deduplicateNameSubstrings(arena_allocator: std.mem.Allocator, nodes: *std.ArrayListUnmanaged(Node)) !void {
    var new_nodes: std.ArrayListUnmanaged(Node) = try .initCapacity(arena_allocator, nodes.items.len);
    new_nodes.expandToCapacity();

    std.mem.sort(Node, nodes.items, {}, struct {
        pub fn lessThan(_: void, lhs: Node, rhs: Node) bool {
            return lhs.name.len > rhs.name.len;
        }
    }.lessThan);

    for (nodes.items, new_nodes.items) |node, *new_node| {
        new_node.* = node;

        for (nodes.items) |other_node| {
            if (node.id != other_node.id) {
                new_node.name = try std.mem.replaceOwned(
                    u8,
                    arena_allocator,
                    new_node.name,
                    other_node.name,
                    try std.fmt.allocPrint(arena_allocator, "{{{}}}", .{other_node.id}),
                );
            }
        }
    }

    nodes.* = new_nodes;

    std.mem.sort(Node, nodes.items, {}, struct {
        pub fn lessThan(_: void, lhs: Node, rhs: Node) bool {
            return lhs.id < rhs.id;
        }
    }.lessThan);
}

pub fn deinit(self: *Graph) void {
    self.arena.deinit();
}
