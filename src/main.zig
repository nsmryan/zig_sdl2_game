const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const assert = @import("std").debug.assert;

const window_width: c_int = 300;
const window_height: c_int = 75;

const Game = struct {
    window: *c.SDL_Window,
    texture: *c.SDL_Texture,
    renderer: *c.SDL_Renderer,

    fn create() !Game {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        if (c.TTF_Init() == -1) {
            c.SDL_Log("Unable to initialize SDL_ttf: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        const window = c.SDL_CreateWindow("Game", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, window_width, window_height, c.SDL_WINDOW_OPENGL) orelse
            {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const zig_bmp = @embedFile("zig.bmp");
        const rw = c.SDL_RWFromConstMem(
            @ptrCast(*const c_void, &zig_bmp[0]),
            @intCast(c_int, zig_bmp.len),
        ) orelse {
            c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        defer assert(c.SDL_RWclose(rw) == 0);

        const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
            c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        defer c.SDL_FreeSurface(zig_surface);

        const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        var game: Game = Game{ .window = window, .texture = zig_texture, .renderer = renderer };
        return game;
    }

    fn destroy(self: *Game) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    fn render(self: *Game) void {
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        c.SDL_RenderPresent(self.renderer);
        _ = c.SDL_RenderClear(self.renderer);
    }

    fn wait_for_frame(self: *Game) void {
        c.SDL_Delay(17);
    }

    fn handle_input(self: *Game) bool {
        var quit = false;

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        return quit;
    }
};

pub fn main() !void {
    var game = try Game.create();
    defer game.destroy();

    var quit = false;
    while (!quit) {
        quit = game.handle_input();

        game.render();

        game.wait_for_frame();
    }
}
