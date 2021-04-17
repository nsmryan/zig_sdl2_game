const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("layout.h");
});
const assert = @import("std").debug.assert;
const mem = @import("std").mem;

const window_width: c_int = 800;
const window_height: c_int = 600;

const State = struct {
    const MAX_LEN: usize = 32;

    text: [MAX_LEN]u8,
    count: u32 = 0,

    fn new() State {
        var state = State{ .text = undefined };
        mem.set(u8, state.text[0..], 0);
        return state;
    }

    fn backspace(self: *State) void {
        if (self.count > 0) {
            self.count -= 1;
            self.text[self.count] = 0;
        }
    }

    fn append(self: *State, chr: u8) void {
        if ((self.count + 1) < MAX_LEN) {
            self.text[self.count] = chr;
            self.count += 1;
        }
    }
};

const Game = struct {
    window: *c.SDL_Window,
    texture: *c.SDL_Texture,
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,

    lay: c.lay_context,

    state: State,

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

        const font = c.TTF_OpenFont("data/Monoid.ttf", 16) orelse {
            c.SDL_Log("Unable to create font from tff: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        var lay: c.lay_context = undefined;
        c.lay_init_context(&lay);
        c.lay_reserve_items_capacity(&lay, 1024);

        const state: State = State.new();
        var game: Game = Game{ .window = window, .texture = zig_texture, .renderer = renderer, .font = font, .state = state, .lay = lay };
        return game;
    }

    fn render_text(self: *Game, text: []const u8, color: c.SDL_Color) !*c.SDL_Texture {
        const c_text = @ptrCast([*c]const u8, text);
        const text_surface = c.TTF_RenderText_Solid(self.font, c_text, color) orelse {
            c.SDL_Log("Unable to create text from font: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const texture = c.SDL_CreateTextureFromSurface(self.renderer, text_surface) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        return texture;
    }

    fn destroy(self: *Game) void {
        c.lay_destroy_context(&self.lay);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    fn render(self: *Game) !void {
        c.lay_reset_context(&self.lay);

        var root = c.lay_item(&self.lay);
        c.lay_set_size_xy(&self.lay, root, 800, 600);
        c.lay_set_contain(&self.lay, root, c.LAY_COLUMN);

        var child = c.lay_item(&self.lay);
        c.lay_insert(&self.lay, root, child);
        c.lay_set_behave(&self.lay, child, c.LAY_CENTER | c.LAY_VFILL | c.LAY_HFILL);

        var margins: c.lay_vec4 = undefined;
        margins.x[0] = 10;
        margins.x[1] = 10;
        margins.x[2] = 10;
        margins.x[3] = 10;
        c.lay_set_margins(&self.lay, child, margins);

        c.lay_run_context(&self.lay);

        const rect = c.lay_get_rect(&self.lay, child);
        c.SDL_Log("rect %d %d %d %d\n", @intCast(c_int, rect.x[0]), @intCast(c_int, rect.x[1]), @intCast(c_int, rect.x[2]), @intCast(c_int, rect.x[3]));

        const width: c_int = 20 * @intCast(c_int, self.state.count);
        const height: c_int = 75;
        const text_rect = c.SDL_Rect{ .x = 0, .y = 0, .w = width, .h = height };

        if (self.state.count > 0) {
            const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
            var texture = try self.render_text(self.state.text[0..], text_color);
            defer c.SDL_DestroyTexture(texture);
            _ = c.SDL_RenderCopy(self.renderer, texture, null, &text_rect);
        }

        //var format: u32 = 0;
        //var w: c_int = 0;
        //var h: c_int = 0;
        //var access: c_int = 0;
        //_ = c.SDL_QueryTexture(texture, &format, &access, &w, &h);

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

                // SDL_Scancode scancode;      /**< SDL physical key code - see ::SDL_Scancode for details */
                // SDL_Keycode sym;            /**< SDL virtual key code - see ::SDL_Keycode for details */
                // Uint16 mod;                 /**< current key modifiers */
                c.SDL_KEYDOWN => {
                    const code: i32 = event.key.keysym.sym;
                    const key: c.SDL_KeyCode = @intToEnum(c.SDL_KeyCode, code);

                    const a_code = @enumToInt(c.SDL_KeyCode.SDLK_a);
                    const z_code = @enumToInt(c.SDL_KeyCode.SDLK_z);

                    if (key == c.SDL_KeyCode.SDLK_RETURN) {
                        c.SDL_Log("Pressed enter");
                    } else if (key == c.SDL_KeyCode.SDLK_ESCAPE) {
                        quit = true;
                    } else if (key == c.SDL_KeyCode.SDLK_SPACE) {
                        self.state.append(@intCast(u8, code));
                    } else if (key == c.SDL_KeyCode.SDLK_BACKSPACE) {
                        self.state.backspace();
                    } else if (code >= a_code and code <= z_code) {
                        self.state.append(@intCast(u8, code));
                    } else {
                        c.SDL_Log("Pressed: %c", key);
                    }
                },

                c.SDL_KEYUP => {},

                c.SDL_MOUSEMOTION => {},

                c.SDL_MOUSEBUTTONDOWN => {},

                c.SDL_MOUSEBUTTONUP => {},

                c.SDL_MOUSEWHEEL => {},

                // just for fun...
                c.SDL_DROPFILE => {
                    c.SDL_Log("Dropped file '%s'", event.drop.file);
                },
                c.SDL_DROPTEXT => {
                    c.SDL_Log("Dropped text '%s'", event.drop.file);
                },
                c.SDL_DROPBEGIN => {
                    c.SDL_Log("Drop start");
                },
                c.SDL_DROPCOMPLETE => {
                    c.SDL_Log("Drop done");
                },

                // could be used for clock tick
                c.SDL_USEREVENT => {},

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

        try game.render();

        game.wait_for_frame();
    }
}
