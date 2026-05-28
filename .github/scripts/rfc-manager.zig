const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const TargetRepo = struct {
    name: []const u8,
    branch_url: ?[]const u8,
    finish: bool,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    const action = args.next() orelse return;
    if (mem.eql(u8, action, "approve")) {
        const rfc_path = args.next() orelse return;
        try approveRfc(init.io, allocator, rfc_path);
    } else if (mem.eql(u8, action, "branch")) {
        const rfc_id = args.next() orelse return;
        const repo_name = args.next() orelse return;
        const branch_url = args.next() orelse return;
        try handleBranchCreated(init.io, allocator, rfc_id, repo_name, branch_url);
    } else if (mem.eql(u8, action, "merge")) {
        const rfc_id = args.next() orelse return;
        const merged_repo = args.next() orelse return;
        const pr_url = args.next() orelse "";
        try handleMerge(init.io, allocator, rfc_id, merged_repo, pr_url);
    }
}

fn approveRfc(io: std.Io, allocator: mem.Allocator, rfc_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var path_parts = mem.tokenizeAny(u8, rfc_path, "/\\");
    _ = path_parts.next();
    const year = path_parts.next() orelse "2026";
    var next_id: u32 = 1;
    var rfcs_root = try cwd.openDir(io, "rfcs", .{ .iterate = true });
    defer rfcs_root.close(io);
    var year_walker = rfcs_root.iterate();
    while (try year_walker.next(io)) |year_entry| {
        if (year_entry.kind != .directory) continue;
        const year_dir_path = try fs.path.join(allocator, &.{ "rfcs", year_entry.name });
        var sub_dir = cwd.openDir(io, year_dir_path, .{ .iterate = true }) catch continue;
        defer sub_dir.close(io);
        var rfc_walker = sub_dir.iterate();
        while (try rfc_walker.next(io)) |rfc_entry| {
            if (rfc_entry.name.len >= 5) {
                const id = std.fmt.parseInt(u32, rfc_entry.name[0..5], 10) catch continue;
                if (id >= next_id) next_id = id + 1;
            }
        }
    }
    const new_id_str = try std.fmt.allocPrint(allocator, "{d:0>5}", .{next_id});
    const old_dir_name = std.fs.path.basename(rfc_path);
    var clean_name = old_dir_name;
    if (old_dir_name.len >= 6 and old_dir_name[5] == '-') clean_name = old_dir_name[6..];
    const new_path = try std.fmt.allocPrint(allocator, "rfcs/{s}/{s}-{s}", .{ year, new_id_str, clean_name });
    try cwd.createDirPath(io, try std.fmt.allocPrint(allocator, "rfcs/{s}", .{year}));
    try std.Io.Dir.rename(cwd, rfc_path, cwd, new_path, io);
    const rfc_file_path = try fs.path.join(allocator, &.{ new_path, "RFC.md" });
    try updateMetadata(io, allocator, rfc_file_path, "Status", "approved");

    const content = try readWholeFile(io, allocator, cwd, rfc_file_path);
    const supersedes = findValue(content, "Supersedes") orelse "";
    if (supersedes.len > 0 and !mem.eql(u8, supersedes, "none") and !mem.eql(u8, supersedes, "-")) {
        if (extractFiveDigitId(supersedes)) |old_id| {
            if (try findRfcPath(io, allocator, old_id)) |old_rfc_path| {
                const new_status = try std.fmt.allocPrint(allocator, "superseded by {s}", .{new_id_str});
                try updateMetadata(io, allocator, old_rfc_path, "Status", new_status);
            }
        }
    }
}

fn handleBranchCreated(io: std.Io, allocator: mem.Allocator, rfc_id: []const u8, repo_name: []const u8, branch_url: []const u8) !void {
    const file_path = try findRfcPath(io, allocator, rfc_id) orelse return;
    const content = try readWholeFile(io, allocator, std.Io.Dir.cwd(), file_path);
    const status = findValue(content, "Status") orelse "";
    const targets_raw = findValue(content, "Target-Repos") orelse return;

    var targets = try parseTargetRepos(allocator, targets_raw);
    defer targets.deinit(allocator);
    const had_any_branch = hasAnyBranchUrl(targets.items);
    var changed = false;
    for (targets.items) |*target| {
        if (mem.eql(u8, target.name, repo_name)) {
            if (target.branch_url == null and branch_url.len > 0) {
                target.branch_url = branch_url;
                changed = true;
            }
        }
    }
    if (!changed) return;

    const serialized = try serializeTargetRepos(allocator, targets.items);
    try updateMetadata(io, allocator, file_path, "Target-Repos", serialized);
    if (mem.eql(u8, status, "approved") and !had_any_branch and hasAnyBranchUrl(targets.items)) {
        try updateMetadata(io, allocator, file_path, "Status", "implementing");
    }
}

fn handleMerge(io: std.Io, allocator: mem.Allocator, rfc_id: []const u8, merged_repo: []const u8, pr_url: []const u8) !void {
    const file_path = try findRfcPath(io, allocator, rfc_id) orelse return;
    const content = try readWholeFile(io, allocator, std.Io.Dir.cwd(), file_path);
    const targets_raw = findValue(content, "Target-Repos") orelse return;
    var targets = try parseTargetRepos(allocator, targets_raw);
    defer targets.deinit(allocator);

    var changed = false;
    for (targets.items) |*target| {
        if (mem.eql(u8, target.name, merged_repo) and !target.finish) {
            target.finish = true;
            changed = true;
        }
    }
    if (!changed) return;

    const serialized = try serializeTargetRepos(allocator, targets.items);
    try updateMetadata(io, allocator, file_path, "Target-Repos", serialized);
    if (pr_url.len > 0) {
        try updateMetadata(io, allocator, file_path, "PR", pr_url);
    }
    if (allTargetsFinished(targets.items)) {
        try updateMetadata(io, allocator, file_path, "Status", "implemented");
    }
}

fn findRfcPath(io: std.Io, allocator: mem.Allocator, rfc_id: []const u8) !?[]const u8 {
    const cwd = std.Io.Dir.cwd();
    var rfcs_root = try cwd.openDir(io, "rfcs", .{ .iterate = true });
    defer rfcs_root.close(io);
    var year_it = rfcs_root.iterate();
    while (try year_it.next(io)) |ye| {
        if (ye.kind != .directory) continue;
        const yp = try fs.path.join(allocator, &.{ "rfcs", ye.name });
        var sd = try cwd.openDir(io, yp, .{ .iterate = true });
        defer sd.close(io);
        var ri = sd.iterate();
        while (try ri.next(io)) |re| {
            if (mem.startsWith(u8, re.name, rfc_id)) return try fs.path.join(allocator, &.{ yp, re.name, "RFC.md" });
        }
    }
    return null;
}

fn updateMetadata(io: std.Io, allocator: mem.Allocator, path: []const u8, field: []const u8, value: []const u8) !void {
    const content = try readWholeFile(io, allocator, std.Io.Dir.cwd(), path);
    var lines = mem.splitSequence(u8, content, "\n");
    var new_c: std.ArrayList(u8) = .empty;
    defer new_c.deinit(allocator);
    const pattern = try std.fmt.allocPrint(allocator, "- **{s}**:", .{field});
    var found: bool = false;
    while (lines.next()) |l| {
        if (mem.containsAtLeast(u8, l, 1, pattern)) {
            found = true;
            try new_c.appendSlice(allocator, "- **");
            try new_c.appendSlice(allocator, field);
            try new_c.appendSlice(allocator, "**: ");
            try new_c.appendSlice(allocator, value);
            try new_c.append(allocator, '\n');
        } else {
            try new_c.appendSlice(allocator, l);
            try new_c.append(allocator, '\n');
        }
    }
    if (!found) {
        try new_c.appendSlice(allocator, "- **");
        try new_c.appendSlice(allocator, field);
        try new_c.appendSlice(allocator, "**: ");
        try new_c.appendSlice(allocator, value);
        try new_c.append(allocator, '\n');
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = new_c.items });
}

fn readWholeFile(io: std.Io, allocator: mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]u8 {
    const stat = try dir.statFile(io, path, .{});
    const size: usize = @intCast(stat.size);
    var buffer = try allocator.alloc(u8, size + 1);
    errdefer allocator.free(buffer);
    const content = try dir.readFile(io, path, buffer);
    return buffer[0..content.len];
}

fn parseTargetRepos(allocator: mem.Allocator, raw: []const u8) !std.ArrayList(TargetRepo) {
    var list: std.ArrayList(TargetRepo) = .empty;
    errdefer list.deinit(allocator);
    var items_it = mem.splitSequence(u8, raw, ",");
    while (items_it.next()) |item_raw| {
        const item = mem.trim(u8, item_raw, " ");
        if (item.len == 0) continue;

        var tokens = mem.tokenizeAny(u8, item, " ");
        const name = tokens.next() orelse continue;
        var target = TargetRepo{ .name = name, .branch_url = null, .finish = false };

        while (tokens.next()) |tok| {
            if (tok.len < 2) continue;
            if (tok[0] == '[' and tok[tok.len - 1] == ']') {
                const marker = tok[1 .. tok.len - 1];
                if (mem.eql(u8, marker, "finish")) {
                    target.finish = true;
                } else if (marker.len > 0) {
                    target.branch_url = marker;
                }
            }
        }
        try list.append(allocator, target);
    }
    return list;
}

fn serializeTargetRepos(allocator: mem.Allocator, targets: []const TargetRepo) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (targets, 0..) |target, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.appendSlice(allocator, target.name);
        if (target.branch_url) |url| {
            try out.appendSlice(allocator, " [");
            try out.appendSlice(allocator, url);
            try out.append(allocator, ']');
        }
        if (target.finish) {
            try out.appendSlice(allocator, " [finish]");
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn allTargetsFinished(targets: []const TargetRepo) bool {
    if (targets.len == 0) return false;
    for (targets) |target| {
        if (!target.finish) return false;
    }
    return true;
}

fn hasAnyBranchUrl(targets: []const TargetRepo) bool {
    for (targets) |target| {
        if (target.branch_url != null) return true;
    }
    return false;
}

fn extractFiveDigitId(value: []const u8) ?[]const u8 {
    if (value.len < 5) return null;
    var i: usize = 0;
    while (i + 5 <= value.len) : (i += 1) {
        if (std.ascii.isDigit(value[i]) and std.ascii.isDigit(value[i + 1]) and std.ascii.isDigit(value[i + 2]) and std.ascii.isDigit(value[i + 3]) and std.ascii.isDigit(value[i + 4])) {
            return value[i .. i + 5];
        }
    }
    return null;
}

fn findValue(content: []const u8, field: []const u8) ?[]const u8 {
    var lines = mem.splitSequence(u8, content, "\n");
    while (lines.next()) |l| {
        if (mem.containsAtLeast(u8, l, 1, field)) {
            var p = mem.splitSequence(u8, l, ":");
            _ = p.next();
            return mem.trim(u8, p.next() orelse "", " ");
        }
    }
    return null;
}
