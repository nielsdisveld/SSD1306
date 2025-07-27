const std = @import("std");
const File = std.fs.File;
const Handle = std.posix.fd_t;

// Device addresses
const DEVICE = "/dev/i2c-1";
const ADDRESS = 0x3c;
const I2C_SLAVE = 0x0703;
const PAGES = 8;

var file: ?File = null;
var handle: ?Handle = null;
//
// Initialize handle to the device to write and read instructions from/to.
pub fn init() !void {
    const f: File = try std.fs.openFileAbsolute(DEVICE, .{ .mode = .read_write });
    // Set I2C address
    if (std.os.linux.ioctl(f.handle, I2C_SLAVE, ADDRESS) < 0)
        return error.IoctlFailed;

    file = f;
    handle = f.handle;
    try sendInitSeq();
}

// Close file
pub fn deinit() void {
    file.?.close();
}

fn sendInitSeq() !void {
    // Send the SSD1306 Initialization Sequence
    std.debug.print("Sending SSD1306 initialization commands...\n", .{});

    // Display OFF (0xAE) - Always start by turning off the display during config
    try sendCommand(0xAE);

    // Set Display Clock Divide Ratio / Oscillator Frequency (0xD5)
    // Bits 3:0 (DCLK) are divide ratio, Bits 7:4 (FREQ) are oscillator frequency
    // Recommended value is 0x80 (Divide Ratio = 1, Freq = 8)
    try sendCommandParam(0xD5, 0x80);

    // Set Multiplex Ratio (0xA8)
    // For 128x64 displays, this is usually 0x3F (63 + 1 = 64 MUX)
    try sendCommandParam(0xA8, 0x3F);

    // Set Display Offset (0xD3) - No offset
    try sendCommandParam(0xD3, 0x00);

    // Set Display Start Line (0x40 to 0x7F) - Set to 0x00 for start line 0
    // This is 0x40 + start_line (0-63). For 0, it's 0x40.
    try sendCommand(0x40);

    // Charge Pump Setting (0x8D) - Enable Charge Pump for internal VCC
    // This command requires parameter 0x14 to enable
    try sendCommandParam(0x8D, 0x14);

    // Set Memory Addressing Mode (0x20)
    // 0x00 = Horizontal Addressing Mode (recommended for graphics)
    // 0x01 = Vertical Addressing Mode
    // 0x02 = Page Addressing Mode (default, often used for text)
    try sendCommandParam(0x20, 0x00);

    // Set Segment Re-map (0xA0 or 0xA1)
    // 0xA0 = Column address 0 mapped to SEG0
    // 0xA1 = Column address 127 mapped to SEG0 (often needed if display is mirrored)
    try sendCommand(0xA1); // Adjust if your display appears mirrored

    // Set COM Output Scan Direction (0xC0 or 0xC8)
    // 0xC0 = Normal mode (COM0 to COM[N-1])
    // 0xC8 = Remapped mode (COM[N-1] to COM0) - often needed if display is upside down
    try sendCommand(0xC8); // Adjust if your display appears upside down

    // Set COM Pins Hardware Configuration (0xDA)
    // For 128x64 displays, usually 0x12 (Alternative COM pin config, Disable COM Left/Right remap)
    // For 128x32 displays, usually 0x02
    try sendCommandParam(0xDA, 0x12);

    // Set Contrast Control (0x81)
    // Value from 0x00 to 0xFF. 0xCF is a common default for good brightness.
    try sendCommandParam(0x81, 0xCF);

    // Set Pre-charge Period (0xD9)
    // Common value is 0xF1 (Phase 1 period = 1 DCLK, Phase 2 period = 15 DCLK)
    try sendCommandParam(0xD9, 0xF1);

    // Set VCOMH Deselect Level (0xDB)
    // Common value is 0x40 (0.77 * VCC)
    try sendCommandParam(0xDB, 0x40);

    // Set Entire Display ON/OFF (0xA4 or 0xA5)
    // 0xA4 = Resume to RAM content display (pixels defined by GDDRAM)
    // 0xA5 = Entire Display ON (all pixels on, ignores GDDRAM)
    try sendCommand(0xA4);

    // Set Normal/Inverse Display (0xA6 or 0xA7)
    // 0xA6 = Normal display (0 in RAM = OFF, 1 in RAM = ON)
    // 0xA7 = Inverse display (0 in RAM = ON, 1 in RAM = OFF)
    try sendCommand(0xA6);

    // Display ON (0xAF) - Finally, turn the display on!
    try sendCommand(0xAF);

    std.debug.print("Display initialized and turned ON. It should now be blank or show garbage, ready for data.\n", .{});

    // Blank screen
    try fillScreen(false);
}

// Send command
fn sendCommand(cmd: u8) !void {
    const h = handle orelse return error.NotInitialized;
    if (std.os.linux.write(h, &[_]u8{ 0x00, cmd }, 2) != 2)
        return error.WriteFailed;
}
// Send command with param
fn sendCommandParam(cmd: u8, param: u8) !void {
    const h = handle orelse return error.NotInitialized;
    if (std.os.linux.write(h, &[_]u8{ 0x00, cmd, param }, 3) != 3)
        return error.WriteFailed;
}

pub fn fillScreen(on: bool) !void {
    try sendCommand(0xB0); // Write to page 0
    try sendCommand(0x00); // Set lower part of column to 0
    try sendCommand(0x10); // Set upper part of column to 0
    var pixel_data_buff: [129]u8 = undefined;
    pixel_data_buff[0] = 0x40; // Write data command
    for (1..129) |i| {
        pixel_data_buff[i] = if (on) 0xFF else 0x00;
    }
    const h = handle orelse return error.NotInitialized;
    for (0..PAGES) |page| {
        const p: u8 = @intCast(page);
        try sendCommand(0xB0 + p);
        if (std.os.linux.write(h, &pixel_data_buff, 129) != 129)
            return error.WriteFailed;
    }
}
