package flxrecord.sinks;

import flxrecord.FrameSink;
import flxrecord.sinks.ImageFormat;
import haxe.io.Bytes;
import StringTools;
import openfl.display.BitmapData;
import openfl.display.JPEGEncoderOptions;
import openfl.display.PNGEncoderOptions;
import sys.FileSystem;
import sys.io.File;

/**
 * Writes every captured frame as its own image plus a `manifest.json` next to them.
 *
 * This is the honest, dependency-free format: any tool can turn the sequence back into a
 * video, and `VideoExport.mux()` does it straight from here when ffmpeg is installed.
 * JPG is the default because encoding a 1080p PNG costs several times more per frame.
 */
class SequenceSink implements FrameSink
{
	public var dir:String;
	public var format:ImageFormat;
	public var quality:Float;
	public var prefix:String;

	/**
	 * Written to the manifest so `VideoExport` knows what the sequence expects.
	 */
	public var audioPath:String;

	var _width:Int = 0;
	var _height:Int = 0;
	var _fps:Float = 30;
	var _frames:Int = 0;

	public function new(dir:String, ?format:ImageFormat, ?quality:Float = 0.9, ?prefix:String = 'frame_')
	{
		this.dir = trimSlash(dir);
		this.format = format != null ? format : JPG;
		this.quality = quality;
		this.prefix = prefix;
	}

	public function open(width:Int, height:Int, fps:Float):Void
	{
		_width = width;
		_height = height;
		_fps = fps;
		_frames = 0;

		makeDirs(dir);
		writeManifest(0);
	}

	public function write(frame:BitmapData, index:Int):Void
	{
		if (frame == null)
			return;

		final bytes = switch (format)
		{
			case PNG: frame.encode(frame.rect, new PNGEncoderOptions());
			case JPG: frame.encode(frame.rect, new JPEGEncoderOptions(qualityInt()));
		}

		if (bytes != null)
			writeEncoded(index, cast bytes);
	}

	/**
	 * Stores an image the caller has already encoded, so a second encode is not paid.
	 */
	public function writeEncoded(index:Int, bytes:Bytes):Void
	{
		if (bytes == null)
			return;

		File.saveBytes(framePath(index), bytes);
		_frames++;
	}

	public function close():Void
	{
		writeManifest(_frames);
	}

	/**
	 * `frames/frame_00001.jpg`, zero padded to five digits so ffmpeg's `%05d` matches.
	 */
	public function framePath(index:Int):String
	{
		return dir + '/' + prefix + StringTools.lpad(Std.string(index + 1), '0', 5) + extension();
	}

	public inline function extension():String
	{
		return format == PNG ? '.png' : '.jpg';
	}

	/**
	 * ffmpeg input pattern matching `framePath()`.
	 */
	public function inputPattern():String
	{
		return dir + '/' + prefix + '%05d' + extension();
	}

	/**
	 * `JPEGEncoderOptions` takes 1..100; `quality` is a 0..1 ratio.
	 */
	public inline function qualityInt():Int
	{
		return Std.int(Math.max(1, Math.min(100, quality * 100)));
	}

	function writeManifest(frames:Int):Void
	{
		final data:Dynamic = {
			width: _width,
			height: _height,
			fps: _fps,
			frames: frames,
			format: extension().substr(1),
			audio: audioPath
		};
		File.saveContent(dir + '/manifest.json', haxe.Json.stringify(data, '  '));
	}

	/**
	 * `sys.FileSystem.createDirectory` only makes one level, and recording folders are
	 * usually nested (`recordings/<song>/<take>`).
	 */
	public static function makeDirs(path:String):Void
	{
		path = trimSlash(path);
		if (path == '' || FileSystem.exists(path))
			return;

		final parent = haxe.io.Path.directory(path);
		if (parent != null && parent != '' && parent != path)
			makeDirs(parent);

		FileSystem.createDirectory(path);
	}

	static function trimSlash(path:String):String
	{
		var p = path;
		while (p.length > 1 && (StringTools.endsWith(p, '/') || StringTools.endsWith(p, '\\')))
			p = p.substr(0, p.length - 1);
		return p;
	}
}
