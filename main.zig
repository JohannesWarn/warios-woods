const std = @import("std");

extern "env" fn js_log(ptr: [*]const u8, len: usize) void;

pub fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    js_log(msg.ptr, msg.len);
}

// Constants

const w = 7;
const h = 11;

const fallDuration = 63;
const explosionDuration = 63;

// Structures

const PlayerInput = packed struct(u8) {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
    a: bool = false,
    b: bool = false,

    _pad: u2 = 0,
};

const ActionState = enum {
    waitingForInput,
    waitingForGame,
    waitingForRelease,
};
const ActionQueue = struct {
    a: ActionState = .waitingForInput,
    b: ActionState = .waitingForInput,
};

// ---

const TileType = enum(u3) {
    empty,
    monster,
    bomb,
    diamond,
    explosion,
    player,

    pub fn isSolid(tile: TileType) bool {
        return switch (tile) {
            .monster, .bomb, .diamond => true,
            else => false,
        };
    }
};
const Tile = packed struct(u16) {
    color: u3,
    tileType: TileType,
    count: u6 = 0,
    willExplode: bool = false,

    _pad: u3 = 0,
};

const empty_tile = Tile{
    .color = 0,
    .tileType = .empty,
};

const player_tile = Tile{
    .color = 0,
    .tileType = .player,
};

// ---

const Sprite = packed struct(u32) {
    w: u2,
    h: u2,
    frameX: u4,
    frameY: u4,
    flipped: bool,
    gx: u4,
    gy: u4,
    px: u4,
    py: u4,

    _pad: u3 = 0,
};

// State

var playerInput = PlayerInput{};
var playerActionQueue = ActionQueue{};
var playerCooldown: u8 = 0;
var tiles: [w * h]Tile = [_]Tile{empty_tile} ** (w * h);
var sprites: [30]Sprite = undefined;
var spritesCount: u8 = 0;

const player: *Sprite = &sprites[0];

var tickCount: u32 = 0;
var bombCount: u32 = 0;

// Exports

pub export fn tiles_ptr() [*]Tile {
    return tiles[0..].ptr;
}

pub export fn tiles_len() usize {
    return @as(usize, tiles.len);
}

pub export fn sprites_ptr() [*]Sprite {
    return sprites[0..].ptr;
}

pub export fn sprites_len() usize {
    return @as(usize, 30);
}

pub export fn sprites_count() u8 {
    return spritesCount;
}

pub export fn player_input_ptr() *PlayerInput {
    return &playerInput;
}

// Functions

pub export fn game_init() void {
    log("hello from game init", .{});

    var i: usize = 0;
    while (i < 7 * 8) : (i += 1) {
        var tileType: TileType = undefined;
        tileType = .monster;

        tiles[i] = Tile{
            .color = @truncate((i + (i % 3) + (3 * i % 5) + (1 * i % 9)) % 8),
            .tileType = tileType,
            .count = 0,
        };
    }

    spritesCount = 1;
    player.* = Sprite{
        .w = 1,
        .h = 2,
        .frameX = 5,
        .frameY = 3,
        .flipped = false,
        .gx = 3,
        .gy = 8,
        .px = 0,
        .py = 0,
    };

    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;
    tiles[playerI] = player_tile;
}

fn startFall() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (player.gy == 0 or tiles[playerI - w].tileType != .empty) {
        return false;
    }

    player.py = 16 - 2;
    player.gy -= 1;
    tiles[playerI - w] = player_tile;

    return true;
}

fn escape() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (!playerInput.up) {
        return false;
    }

    if (playerI + w >= w * h) {
        return false;
    }

    if (!tiles[playerI + w].tileType.isSolid()) {
        return false;
    }

    tiles[playerI] = tiles[playerI + w];
    tiles[playerI + w] = player_tile;
    player.gy += 1;

    return true;
}

fn turnAround() bool {
    if (playerInput.left and !player.flipped) {
        player.flipped = true;
        return true;
    }

    if (playerInput.right and player.flipped) {
        player.flipped = false;
        return true;
    }

    return false;
}

fn startWalk() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    var nextI: usize = undefined;
    if (playerInput.left) {
        if (gx == 0) {
            return false;
        }
        nextI = playerI - 1;
    } else if (playerInput.right) {
        if (gx == w - 1) {
            return false;
        }
        nextI = playerI + 1;
    } else {
        return false;
    }

    if (!(tiles[nextI].tileType == .empty or tiles[nextI].tileType == .player)) {
        return false;
    }

    if (playerInput.left) {
        var offset: usize = 0;
        while (playerI + w - 1 + offset < w * h and tiles[playerI + w - 1 + offset].tileType == .empty and tiles[playerI + w + offset].tileType.isSolid()) {
            tiles[playerI + w - 1 + offset] = tiles[playerI + w + offset];
            tiles[playerI + w + offset] = empty_tile;

            offset += w;
        }
        player.gx -= 1;
        player.px = 16 - 1;
    } else if (playerInput.right) {
        var offset: usize = 0;
        while (playerI + w + 1 + offset < w * h and tiles[playerI + w + 1 + offset].tileType == .empty and tiles[playerI + w + offset].tileType.isSolid()) {
            tiles[playerI + w + 1 + offset] = tiles[playerI + w + offset];
            tiles[playerI + w + offset] = empty_tile;

            offset += w;
        }
        player.px += 1;
    }

    tiles[nextI] = player_tile;

    return true;
}

fn pickUpAll() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (gy == h - 1) {
        return false;
    }

    if (playerActionQueue.b != .waitingForGame) {
        return false;
    }

    if (tiles[playerI + w].tileType != .empty) {
        return false;
    }

    var sourceI: usize = undefined;
    if (player.flipped) {
        if (player.gx == 0) {
            return false;
        }

        sourceI = playerI - 1;
    } else {
        if (player.gx == w - 1) {
            return false;
        }

        sourceI = playerI + 1;
    }

    if (!tiles[sourceI].tileType.isSolid()) {
        if (tiles[sourceI].tileType == .explosion) {
            return false;
        }
        if (sourceI < w) {
            return false;
        }
        sourceI -= w;
    }
    if (!tiles[sourceI].tileType.isSolid()) {
        return false;
    }

    var offset: usize = 0;
    while (sourceI + w * offset < w * h and tiles[sourceI + w * offset].tileType.isSolid()) {
        if (playerI + w + w * offset >= w * h) {
            return false;
        }
        if (tiles[playerI + w + w * offset].tileType != .empty) {
            return false;
        }

        offset += 1;
    }

    offset = 0;
    while (sourceI + w * offset < w * h and tiles[sourceI + w * offset].tileType.isSolid()) {
        tiles[playerI + w + w * offset] = tiles[sourceI + w * offset];
        tiles[sourceI + w * offset] = empty_tile;

        offset += 1;
    }

    return true;
}

fn placeAll() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (gy == h - 1) {
        return false;
    }

    if (playerActionQueue.b != .waitingForGame) {
        return false;
    }

    if (!tiles[playerI + w].tileType.isSolid()) {
        return false;
    }

    var destinationI: usize = undefined;
    if (player.flipped) {
        if (player.gx == 0) {
            return false;
        }

        destinationI = playerI - 1;
    } else {
        if (player.gx == w - 1) {
            return false;
        }

        destinationI = playerI + 1;
    }

    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        destinationI += w;
        if (destinationI >= w * h) {
            return false;
        }
    }
    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        destinationI += w;
        if (destinationI >= w * h) {
            return false;
        }
    }
    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        return false;
    }

    var offset: usize = 0;
    while (playerI + w + offset < w * h and tiles[playerI + w + offset].tileType.isSolid()) {
        if (destinationI + offset >= w * h) {
            return false;
        }
        const destinationTileType = tiles[destinationI + offset].tileType;
        if (!(destinationTileType == .empty or destinationTileType == .player)) {
            return false;
        }

        offset += w;
    }

    offset = 0;
    while (playerI + w + offset < w * h and tiles[playerI + w + offset].tileType.isSolid()) {
        tiles[destinationI + offset] = tiles[playerI + w + offset];
        tiles[playerI + w + offset] = empty_tile;

        offset += w;
    }

    return true;
}

fn pickUpSingle() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (gy == h - 1) {
        return false;
    }

    if (playerActionQueue.a != .waitingForGame) {
        return false;
    }

    if (tiles[playerI + w].tileType != .empty) {
        return false;
    }

    var sourceI: usize = undefined;
    if (player.flipped) {
        if (player.gx == 0) {
            return false;
        }

        sourceI = playerI - 1;
    } else {
        if (player.gx == w - 1) {
            return false;
        }

        sourceI = playerI + 1;
    }

    const tileInfront = tiles[sourceI];
    if (!tileInfront.tileType.isSolid()) {
        if (tileInfront.tileType == .explosion) {
            return false;
        }
        if (sourceI < w) {
            return false;
        }
        sourceI -= w;
    }

    if (!tiles[sourceI].tileType.isSolid()) {
        return false;
    }

    tiles[playerI + w] = tiles[sourceI];
    tiles[sourceI] = player_tile;
    tiles[sourceI].count = 15;

    return true;
}

fn placeSingle() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (gy == h - 1) {
        return false;
    }

    if (playerActionQueue.a != .waitingForGame) {
        return false;
    }

    if (!tiles[playerI + w].tileType.isSolid()) {
        return false;
    }

    var destinationI: usize = undefined;
    if (player.flipped) {
        if (player.gx == 0) {
            return false;
        }

        destinationI = playerI - 1;
    } else {
        if (player.gx == w - 1) {
            return false;
        }

        destinationI = playerI + 1;
    }

    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        destinationI += w;
        if (destinationI >= w * h) {
            return false;
        }
    }
    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        destinationI += w;
        if (destinationI >= w * h) {
            return false;
        }
    }
    if (!(tiles[destinationI].tileType == .empty or tiles[destinationI].tileType == .player)) {
        return false;
    }

    tiles[destinationI] = tiles[playerI + w];
    tiles[playerI + w] = empty_tile;

    return true;
}

fn fallPixels() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (player.py == 0) {
        return false;
    }

    player.py -= 2;
    if (player.py == 0) {
        if (tiles[playerI + w].tileType == .player) {
            tiles[playerI + w] = empty_tile;
        }
    }

    return true;
}

fn walkPixels() bool {
    const gx: usize = player.gx;
    const gy: usize = player.gy;
    const playerI: usize = gx + gy * w;

    if (player.px == 0) {
        return false;
    }

    if (player.flipped) {
        player.px -= 1;
        if (player.px == 0) {
            if (tiles[playerI + 1].tileType == .player) {
                tiles[playerI + 1] = empty_tile;
            }
        }
    } else {
        if (player.px == 15) {
            player.px = 0;
            player.gx += 1;
            if (tiles[playerI].tileType == .player) {
                tiles[playerI] = empty_tile;
            }
        } else {
            player.px += 1;
        }
    }
    return true;
}

fn movePlayer() void {
    if (playerInput.a) {
        if (playerActionQueue.a == .waitingForInput) {
            playerActionQueue.a = .waitingForGame;
        }
    } else {
        if (playerActionQueue.a == .waitingForRelease) {
            playerActionQueue.a = .waitingForInput;
        }
    }

    if (playerInput.b) {
        if (playerActionQueue.b == .waitingForInput) {
            playerActionQueue.b = .waitingForGame;
        }
    } else {
        if (playerActionQueue.b == .waitingForRelease) {
            playerActionQueue.b = .waitingForInput;
        }
    }

    if (playerCooldown != 0) {
        playerCooldown -= 1;
    }

    if (fallPixels()) {
        return;
    }

    if (walkPixels()) {
        return;
    }

    if (turnAround()) {
        playerCooldown = 6;
        return;
    }

    if (playerCooldown == 0) {
        if (pickUpAll()) {
            playerCooldown = 10;
            playerActionQueue.b = .waitingForRelease;
            return;
        }
        if (placeAll()) {
            playerCooldown = 10;
            playerActionQueue.b = .waitingForRelease;
            return;
        }
        if (playerActionQueue.b == .waitingForGame) {
            playerActionQueue.b = .waitingForRelease;
        }

        if (pickUpSingle()) {
            playerCooldown = 10;
            playerActionQueue.a = .waitingForRelease;
            return;
        }
        if (placeSingle()) {
            playerCooldown = 10;
            playerActionQueue.a = .waitingForRelease;
            return;
        }
        if (playerActionQueue.a == .waitingForGame) {
            playerActionQueue.a = .waitingForRelease;
        }

        if (escape()) {
            return;
        }
    }

    if (startFall()) {
        return;
    }

    if (playerCooldown == 0) {
        if (startWalk()) {
            return;
        }
    }
}

pub export fn tick() void {
    tickCount += 1;

    movePlayer();

    // tick all counts down
    var i: usize = 0;
    while (i < w * h) : (i += 1) {
        const tile = tiles[i];

        if (tile.count != 0) {
            if (tile.tileType == .player and tile.count == 1) {
                tiles[i] = empty_tile;
                continue;
            }

            if (playerInput.down and tile.tileType.isSolid()) {
                tiles[i].count -= @min(tile.count, 10);
            } else {
                tiles[i].count -= 1;
            }
        }
    }

    // move falling tiles
    i = 0;
    while (i < w * (h - 1)) : (i += 1) {
        const tileAbove = tiles[i + w];

        if (!tileAbove.tileType.isSolid()) {
            continue;
        }

        if (tiles[i].tileType == .empty and tileAbove.count == 0) {
            tiles[i] = tileAbove;
            if ((i < w) or (tiles[i - w].tileType != .empty)) {
                tiles[i].count = 0;
            } else {
                tiles[i].count = fallDuration;
            }
            tiles[i + w] = empty_tile;
        }
    }

    // find explosions
    i = 0;
    var color: u3 = 0;
    var count: u4 = 0;
    var hasSeenBomb = false;
    var conditionsSatisfied = false;
    while (i < paths.len) : (i += 1) {
        const j = paths[i];

        if (j == pathBreak) {
            count = 0;
            continue;
        }

        const tile = tiles[j];

        if (!tile.tileType.isSolid() or tile.count != 0) {
            count = 0;
            continue;
        }

        if (count == 0 or tile.color != color) {
            conditionsSatisfied = false;
            hasSeenBomb = tile.tileType == .bomb;
            color = tile.color;
            count = 1;
            continue;
        }

        count += 1;

        if (!hasSeenBomb) {
            hasSeenBomb = tile.tileType == .bomb;
        }

        if (conditionsSatisfied) {
            tiles[j].willExplode = true;
        } else if (count >= 3 and hasSeenBomb) {
            conditionsSatisfied = true;
            tiles[j].willExplode = true;

            var k: u8 = 1;
            while (k < count) {
                tiles[paths[i - k]].willExplode = true;
                k += 1;
            }
        }
    }

    // explode bombs and remove finished explosions
    i = 0;
    while (i < w * h) : (i += 1) {
        var tile = tiles[i];

        if (tile.willExplode) {
            tile.tileType = .explosion;
            tile.count = explosionDuration;
            tile.willExplode = false;
            tiles[i] = tile;
        }

        if (tile.tileType == .explosion and tile.count == 0) {
            tiles[i] = empty_tile;
        }
    }

    // add new bombs
    if ((tickCount + 190) % 200 == 0) {
        defer {
            bombCount += 1;
        }

        const x: usize = @truncate((bombCount + bombCount % 3 + bombCount % 4) % 8);
        if (tiles[w * h - 1 - x].tileType == .empty) {
            var tileType: TileType = undefined;
            if (bombCount % 5 == 0) {
                tileType = .monster;
            } else {
                tileType = .bomb;
            }

            tiles[w * h - 1 - x] = Tile{
                .color = @truncate(((bombCount % 5) + bombCount) % 8),
                .tileType = tileType,
                .count = fallDuration,
            };
        }
    }
}

// Path calculation

const pathCount = 338;
const pathBreak = 127;
fn calculatePaths() [pathCount]u7 {
    var p: [pathCount]u7 = [_]u7{pathBreak} ** pathCount;

    var i = 0;

    // horizontal
    for (0..w) |x| {
        for (0..h) |y| {
            p[i] = x + y * w;
            i += 1;
        }
        i += 1;
    }

    // vertical
    for (0..h) |y| {
        for (0..w) |x| {
            p[i] = x + y * w;
            i += 1;
        }
        i += 1;
    }

    var x = 0;
    var y = 0;

    // diagonal /
    x = w - 3;
    y = 0;
    while (true) {
        if (y < h) {
            p[i] = x + y * w;
            i += 1;
        }

        if (x == w - 1) {
            if (y >= w - 1) {
                x = 0;
                y = y - w + 2;
                if (y == h - 2) {
                    break;
                }
            } else {
                x = w - y - 2;
                y = 0;
            }

            i += 1;
        } else {
            x += 1;
            y += 1;
        }
    }

    // diagonal \
    x = 2;
    y = 0;
    while (true) {
        if (y < h) {
            p[i] = x + y * w;
            i += 1;
        }

        if (x == 0) {
            x = y + 1;
            y = 0;

            if (x > w - 1) {
                y = x - (w - 1);
                x = w - 1;

                if (y == h - 2) {
                    break;
                }
            }

            i += 1;
        } else {
            x -= 1;
            y += 1;
        }
    }

    return p;
}

const paths = calculatePaths();
