const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("layout.h");
});
const assert = @import("std").debug.assert;
const mem = @import("std").mem;
const fs = @import("std").fs;

const window_width: c_int = 800;
const window_height: c_int = 600;

const NUM_DIRS: i32 = 5;
const NUM_SYMS: i32 = 10;

const State = struct {
    const MAX_LEN: usize = 32;

    text: [MAX_LEN]u8,
    count: u32 = 0,

    code: [NUM_DIRS][NUM_SYMS]u8,

    mouse: c.SDL_Point,

    fn new() State {
        const mouse = c.SDL_Point{ .x = 0, .y = 0 };
        var state = State{ .text = undefined, .code = undefined, .mouse = mouse };
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

const Layout = struct {
    lay: c.lay_context,

    main: c.SDL_Rect,
    prog: c.SDL_Rect,
    entries: [NUM_DIRS][NUM_SYMS]c.SDL_Rect,

    fn new() Layout {
        var lay: c.lay_context = undefined;
        c.lay_init_context(&lay);
        c.lay_reserve_items_capacity(&lay, 1024);

        var zero_vec: c.SDL_Rect = c.SDL_Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        return Layout{ .lay = lay, .main = zero_vec, .prog = zero_vec, .entries = undefined };
    }

    fn destroy(self: *Layout) void {
        c.lay_destroy_context(&self.lay);
    }

    fn layout(self: *Layout) void {
        // Initialize
        c.lay_reset_context(&self.lay);

        // Root
        var root = c.lay_item(&self.lay);
        c.lay_set_size_xy(&self.lay, root, window_width, window_height);
        c.lay_set_contain(&self.lay, root, c.LAY_COLUMN);

        // Main Game Window
        var main_item = c.lay_item(&self.lay);
        c.lay_insert(&self.lay, root, main_item);
        c.lay_set_behave(&self.lay, main_item, c.LAY_CENTER | c.LAY_VFILL | c.LAY_HFILL);

        {
            var margins: c.lay_vec4 = undefined;
            margins.x[0] = 3;
            margins.x[1] = 3;
            margins.x[2] = 3;
            margins.x[3] = 3;
            c.lay_set_margins(&self.lay, main_item, margins);
        }

        // Program Window
        var prog_item = c.lay_item(&self.lay);
        c.lay_insert(&self.lay, root, prog_item);
        c.lay_set_behave(&self.lay, prog_item, c.LAY_CENTER | c.LAY_VFILL | c.LAY_HFILL);
        c.lay_set_contain(&self.lay, prog_item, c.LAY_COLUMN);

        {
            var margins: c.lay_vec4 = undefined;
            margins.x[0] = 3;
            margins.x[1] = 3;
            margins.x[2] = 3;
            margins.x[3] = 3;
            c.lay_set_margins(&self.lay, prog_item, margins);
        }

        // Symbol Entries
        var entry_items: [NUM_DIRS][NUM_SYMS]c.lay_id = undefined;
        var list_index: u32 = 0;
        while (list_index < NUM_DIRS) : (list_index += 1) {
            var row = c.lay_item(&self.lay);
            c.lay_set_behave(&self.lay, row, c.LAY_CENTER | c.LAY_VFILL | c.LAY_HFILL);
            c.lay_set_contain(&self.lay, row, c.LAY_ROW);
            c.lay_insert(&self.lay, prog_item, row);

            var entry_index: u32 = 0;
            while (entry_index < NUM_SYMS) : (entry_index += 1) {
                var item = c.lay_item(&self.lay);

                var margins: c.lay_vec4 = undefined;
                margins.x[0] = 1;
                margins.x[1] = 1;
                margins.x[2] = 1;
                margins.x[3] = 1;
                c.lay_set_margins(&self.lay, item, margins);
                c.lay_set_behave(&self.lay, item, c.LAY_CENTER | c.LAY_VFILL | c.LAY_HFILL);

                c.lay_insert(&self.lay, row, item);

                entry_items[list_index][entry_index] = item;
            }
        }

        // Layout Screen
        c.lay_run_context(&self.lay);

        // Retrieve Rects
        self.main = layout_to_sdl_rect(c.lay_get_rect(&self.lay, main_item));
        self.prog = layout_to_sdl_rect(c.lay_get_rect(&self.lay, prog_item));

        list_index = 0;
        while (list_index < NUM_DIRS) : (list_index += 1) {
            var entry_index: u32 = 0;
            while (entry_index < NUM_SYMS) : (entry_index += 1) {
                const item: c.lay_id = entry_items[list_index][entry_index];
                const lay_rect = c.lay_get_rect(&self.lay, item);
                const rect = layout_to_sdl_rect(lay_rect);
                self.entries[list_index][entry_index] = rect;
            }
        }
    }
};

const Game = struct {
    window: *c.SDL_Window,
    tiles: *c.SDL_Texture,
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,

    layout: Layout,
    state: State,

    fn create() !Game {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        _ = c.SDL_ShowCursor(0);

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

        const tile_surface = c.IMG_Load("data/tiles.png") orelse {
            c.SDL_Log("Unable to load tiles.png: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        defer c.SDL_FreeSurface(tile_surface);

        const tile_texture = c.SDL_CreateTextureFromSurface(renderer, tile_surface) orelse {
            c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        //const zig_bmp = @embedFile("zig.bmp");
        //const rw = c.SDL_RWFromConstMem(
        //    @ptrCast(*const c_void, &zig_bmp[0]),
        //    @intCast(c_int, zig_bmp.len),
        //) orelse {
        //    c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
        //    return error.SDLInitializationFailed;
        //};
        //defer assert(c.SDL_RWclose(rw) == 0);

        //const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
        //    c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
        //    return error.SDLInitializationFailed;
        //};
        //defer c.SDL_FreeSurface(zig_surface);

        //const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
        //    c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        //    return error.SDLInitializationFailed;
        //};

        const font = c.TTF_OpenFont("data/Consolas.ttf", 20) orelse {
            c.SDL_Log("Unable to create font from tff: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const layout = Layout.new();
        const state: State = State.new();
        var game: Game = Game{ .window = window, .tiles = tile_texture, .renderer = renderer, .font = font, .state = state, .layout = layout };
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
        self.layout.destroy();
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyTexture(self.tiles);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    fn render(self: *Game) !void {
        self.layout.layout();

        // Outline Entries
        const width: c_int = 10 * @intCast(c_int, self.state.count);
        const height: c_int = 30;
        const text_rect = c.SDL_Rect{ .x = self.layout.prog.x, .y = self.layout.prog.y, .w = width, .h = height };

        var list_index: u32 = 0;
        while (list_index < NUM_DIRS) : (list_index += 1) {
            var entry_index: u32 = 0;
            while (entry_index < NUM_SYMS) : (entry_index += 1) {
                _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
                _ = c.SDL_RenderDrawRect(self.renderer, &self.layout.entries[list_index][entry_index]);
            }
        }

        // Print Text
        if (self.state.count > 0) {
            const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
            var texture = try self.render_text(self.state.text[0..], text_color);
            defer c.SDL_DestroyTexture(texture);
            _ = c.SDL_RenderCopy(self.renderer, texture, null, &text_rect);
        }

        // Outline Screen Sections
        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderDrawRect(self.renderer, &self.layout.main);

        _ = c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderDrawRect(self.renderer, &self.layout.prog);

        // Tile Test
        const in_x = self.state.mouse.x >= self.layout.main.x and self.state.mouse.x < (self.layout.main.x + self.layout.main.w - 16);
        const in_y = self.state.mouse.y >= self.layout.main.y and self.state.mouse.y < (self.layout.main.y + self.layout.main.h - 16);
        if (in_x and in_y) {
            const src_rect = c.SDL_Rect{ .x = 16 * 15, .y = 16 * 15, .w = 16, .h = 16 };
            const dst_rect = c.SDL_Rect{ .x = self.state.mouse.x, .y = self.state.mouse.y, .w = 16, .h = 16 };
            _ = c.SDL_RenderCopy(self.renderer, self.tiles, &src_rect, &dst_rect);
        }

        //var format: u32 = 0;
        //var w: c_int = 0;
        //var h: c_int = 0;
        //var access: c_int = 0;
        //_ = c.SDL_QueryTexture(texture, &format, &access, &w, &h);

        c.SDL_RenderPresent(self.renderer);
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0);
        _ = c.SDL_RenderClear(self.renderer);
    }

    fn wait_for_frame(self: *Game) void {
        c.SDL_Delay(17);
    }

    fn read_config(self: *Game) void {
        const flags = fs.File.OpenFlags{ .read = true, .write = false, .lock = fs.File.Lock.None };
        const config = fs.cwd().openFile("config.txt", flags);
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

                c.SDL_MOUSEMOTION => {
                    self.state.mouse = c.SDL_Point{ .x = event.motion.x, .y = event.motion.y };
                },

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

fn layout_to_sdl_rect(vec: c.lay_vec4) c.SDL_Rect {
    return c.SDL_Rect{ .x = vec.x[0], .y = vec.x[1], .w = vec.x[2], .h = vec.x[3] };
}

pub fn main() !void {
    var game = try Game.create();
    defer game.destroy();

    var quit = false;
    while (!quit) {
        quit = game.handle_input();

        try game.render();

        game.read_config();

        game.wait_for_frame();
    }
}
