const std = @import("std");

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
var playerInput = PlayerInput{};

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

pub export fn tiles_len() u32 {
    return @as(u32, tiles.len);
}

pub export fn sprites_ptr() [*]Sprite {
    return sprites[0..].ptr;
}

pub export fn sprites_len() u32 {
    return @as(u32, 30);
}

pub export fn sprites_count() u8 {
    return spritesCount;
}

pub export fn player_input_ptr() *PlayerInput {
    return &playerInput;
}

// Functions

pub export fn game_init() void {
    var i: u8 = 0;
    while (i < 7 * 3) {
        defer {
            i += 1;
        }

        var tileType: TileType = undefined;
        tileType = .monster;

        tiles[i] = Tile{
            .color = @truncate((i) % 3),
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

    const playerI = @as(u32, player.gx) + @as(u32, player.gy) * w;
    tiles[playerI] = player_tile;
}

fn fall() bool {
    const playerI = @as(u32, player.gx) + @as(u32, player.gy) * w;

    if (player.gy == 0 or tiles[playerI - w].tileType != .empty) {
        return false;
    }

    player.py -= 2;
    player.gy -= 1;
    tiles[playerI - w] = player_tile;

    return true;
}

fn escape() bool {
    const playerI = @as(u32, player.gx) + @as(u32, player.gy) * w;

    if (!playerInput.up or !tiles[playerI + w].tileType.isSolid()) {
        return false;
    }

    tiles[playerI] = tiles[playerI + w];
    tiles[playerI + w] = player_tile;
    player.gy += 1;

    return true;
}

fn walk() bool {
    const gx: u32 = player.gx;
    const gy: u32 = player.gy;

    const playerI: u32 = gx + gy * w;

    var targetFlipped: bool = undefined;
    var nextI: u32 = undefined;
    var edgeX: u32 = undefined;
    if (playerInput.left) {
        targetFlipped = true;
        nextI = playerI - 1;
        edgeX = 0;
    } else if (playerInput.right) {
        targetFlipped = false;
        nextI = playerI + 1;
        edgeX = w - 1;
    } else {
        return false;
    }

    if (player.flipped != targetFlipped) {
        player.flipped = targetFlipped;
        return true;
    }

    if (tiles[nextI].tileType != .empty) {
        return false;
    }

    if (gx == edgeX) {
        return false;
    }

    if (playerInput.left) {
        if (tiles[playerI + w - 1].tileType == .empty) {
            tiles[playerI + w - 1] = tiles[playerI + w];
            tiles[playerI + w] = empty_tile;
        }
        player.gx -= 1;
        player.px -= 1;
    } else if (playerInput.right) {
        if (tiles[playerI + w + 1].tileType == .empty) {
            tiles[playerI + w + 1] = tiles[playerI + w];
            tiles[playerI + w] = empty_tile;
        }
        player.px += 1;
    }

    tiles[nextI] = player_tile;

    return true;
}

fn pickUp() bool {
    const gx: u32 = player.gx;
    const gy: u32 = player.gy;

    const playerI: u32 = gx + gy * w;

    if (!playerInput.a) {
        return false;
    }

    if (tiles[playerI + w].tileType != .empty) {
        return false;
    }

    var sourceI: u32 = undefined;
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

    if (tiles[sourceI].tileType == .empty) {
        sourceI -= w;
    }
    if (tiles[sourceI].tileType == .empty) {
        return false;
    }

    tiles[playerI + w] = tiles[sourceI];
    tiles[sourceI] = empty_tile;

    return true;
}

fn placeSingle() bool {
    const gx: u32 = player.gx;
    const gy: u32 = player.gy;

    const playerI: u32 = gx + gy * w;

    if (!playerInput.a) {
        return false;
    }

    if (tiles[playerI + w].tileType == .empty) {
        return false;
    }

    var destinationI: u32 = undefined;
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

    if (tiles[destinationI].tileType != .empty) {
        destinationI += w;
    }
    if (tiles[destinationI].tileType != .empty) {
        destinationI += w;
    }
    if (tiles[destinationI].tileType != .empty) {
        return false;
    }

    tiles[destinationI] = tiles[playerI + w];
    tiles[playerI + w] = empty_tile;

    return true;
}

fn movePlayer() void {
    if (fall()) {
        return;
    }

    if (escape()) {
        return;
    }

    if (walk()) {
        return;
    }

    if (pickUp()) {
        return;
    }

    if (placeSingle()) {
        return;
    }
}

pub export fn tick() void {
    tickCount += 1;

    var i: u16 = 0;

    const playerI = @as(u32, player.gx) + @as(u32, player.gy) * w;
    if (player.px == 0 and player.py == 0) {
        movePlayer();
    } else {
        if (player.py != 0) {
            player.py -= 2;
            if (player.py == 0) {
                if (tiles[playerI + w].tileType == .player) {
                    tiles[playerI + w] = empty_tile;
                }
            }
        } else {
            if (player.flipped) {
                player.px -= 1;
                if (player.px == 0) {
                    if (tiles[playerI + 1].tileType == .player) {
                        tiles[playerI + 1] = empty_tile;
                    }
                }
            } else {
                player.px += 1;
                if (player.px == 0) {
                    player.gx += 1;
                    if (tiles[playerI].tileType == .player) {
                        tiles[playerI] = empty_tile;
                    }
                }
            }
        }
    }

    // tick all counts down
    i = 0;
    while (i < w * h) {
        defer {
            i += 1;
        }

        if (tiles[i].count != 0) {
            if (playerInput.down and tiles[i].tileType != .explosion) {
                tiles[i].count -= @min(tiles[i].count, 10);
            } else {
                tiles[i].count -= 1;
            }
        }
    }

    // move falling tiles
    i = 0;
    while (i < w * (h - 1)) {
        defer {
            i += 1;
        }

        if (tiles[i + w].tileType == .player) {
            continue;
        }

        if (tiles[i].tileType == .empty and tiles[i + w].count == 0 and tiles[i + w].tileType != .empty and tiles[i + w].tileType != .explosion) {
            tiles[i] = tiles[i + w];
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
    while (i < paths.len) {
        defer {
            i += 1;
        }

        const j = paths[i];

        if (j == pathBreak) {
            count = 0;
            continue;
        }

        if (tiles[j].tileType == .empty or tiles[j].tileType == .player or tiles[j].tileType == .explosion or tiles[j].count != 0) {
            count = 0;
            continue;
        }

        if (count == 0 or tiles[j].color != color) {
            conditionsSatisfied = false;
            hasSeenBomb = tiles[j].tileType == .bomb;
            color = tiles[j].color;
            count = 1;
            continue;
        }

        if (tiles[j].color == color) {
            count += 1;

            if (!hasSeenBomb) {
                hasSeenBomb = tiles[j].tileType == .bomb;
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
    }

    // explode bombs and remove finished explosions
    i = 0;
    while (i < w * h) {
        defer {
            i += 1;
        }

        if (tiles[i].willExplode) {
            tiles[i].tileType = .explosion;
            tiles[i].count = explosionDuration;
            tiles[i].willExplode = false;
        }

        if (tiles[i].tileType == .explosion and tiles[i].count == 0) {
            tiles[i] = empty_tile;
        }
    }

    // add new bombs
    if ((tickCount + 190) % 200 == 0) {
        defer {
            bombCount += 1;
        }

        const x: u32 = @truncate((bombCount + bombCount % 3 + bombCount % 4) % 8);
        if (tiles[w * h - 1 - x].tileType == .empty) {
            var tileType: TileType = undefined;
            if (bombCount % 3 == 0) {
                tileType = .monster;
            } else {
                tileType = .bomb;
            }

            tiles[w * h - 1 - x] = Tile{
                .color = @truncate(((bombCount % 5) + bombCount) % 3),
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
