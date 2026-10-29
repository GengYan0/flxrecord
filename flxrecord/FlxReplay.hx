package flxrecord;

import flxrecord.sinks.ImageFormat;
import flxrecord.sinks.SequenceSink;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display.JPEGEncoderOptions;

/**
 * Ring buffer of the last `seconds` of frames, kept as JPEG bytes: 1080p RGBA is 8 MB per
 * frame, the same frame as JPEG is around 150 KB.
 */
class FlxReplay implements FrameSink
{
	/**
	 * How many seconds of history to keep.
	 */
	public var seconds(default, set):Float = 10;

	/**
	 * Capture rate. Matches the recorder that feeds this sink.
	 */
	public var fps(default, set):Float = 30;

	public var quality:Float = 0.85;

	public var active(default, null):Bool = false;

	/**
	 * Audio file to mux with the dump, if the game knows which track was playing.
	 */
	public var audioPath:String;

	var _ring:Array<Bytes> = [];
	var _next:Int = 0;
	var _filled:Int = 0;
	var _width:Int = 0;
	var _height:Int = 0;
	var _encoder:JPEGEncoderOptions;
	var _encoderQuality:Int = -1;

	public function new(?seconds:Float = 10, ?fps:Float = 30, ?quality:Float = 0.85)
	{
		this.seconds = seconds;
		this.fps = fps;
		this.quality = quality;
	}

	public function open(width:Int, height:Int, fps:Float):Void
	{
		_width = width;
		_height = height;
		this.fps = fps;
		clear();
		active = true;
	}

	public function write(frame:BitmapData, index:Int):Void
	{
		if (frame == null || !active)
			return;

		final bytes:Bytes = cast frame.encode(frame.rect, encoder());

		if (bytes == null)
			return;

		ensureCapacity();

		_ring[_next] = bytes;
		_next = (_next + 1) % _ring.length;
		if (_filled < _ring.length)
			_filled++;
	}

	public function close():Void
	{
		active = false;
	}

	/**
	 * Drops the buffered history but keeps the buffer allocated.
	 */
	public function clear():Void
	{
		_ring = [];
		_next = 0;
		_filled = 0;
		ensureCapacity();
	}

	public inline function frameCount():Int
	{
		return _filled;
	}

	/**
	 * How many seconds are actually buffered right now.
	 */
	public inline function bufferedSeconds():Float
	{
		return fps > 0 ? _filled / fps : 0;
	}

	/**
	 * Writes the buffered frames to `dir` in the same layout `SequenceSink` uses, so the
	 * result can be muxed by `VideoExport`.
	 *
	 * @param	dir		Target folder.
	 * @param	audio	Track to record in the manifest; falls back to `audioPath`.
	 */
	public function dump(dir:String, ?audio:String):SequenceSink
	{
		if (_filled == 0)
			return null;

		final sink = new SequenceSink(dir, JPG, quality);
		sink.audioPath = audio != null ? audio : audioPath;
		sink.open(_width, _height, fps);

		// Oldest frame first, starting right after the next write slot.
		final start = _filled == _ring.length ? _next : 0;
		for (i in 0..._filled)
		{
			final bytes = _ring[(start + i) % _ring.length];
			if (bytes != null)
				sink.writeEncoded(i, bytes);
		}

		sink.close();
		return sink;
	}

	/**
	 * Dumps the buffer and turns it into a video in one go.
	 * Returns the video path, or `null` when ffmpeg is unavailable.
	 */
	public function save(dir:String, ?audio:String, ?out:String):String
	{
		final track = audio != null ? audio : audioPath;
		final sink = dump(dir, track);
		if (sink == null)
			return null;

		final target = out != null ? out : sink.dir + '/replay.mp4';
		return VideoExport.mux(sink, track, target) ? target : null;
	}

	/**
	 * `JPEGEncoderOptions` is rebuilt only when `quality` actually moves; `qualityInt()` is
	 * the same rounding `SequenceSink` uses.
	 */
	function encoder():JPEGEncoderOptions
	{
		final q = Std.int(Math.max(1, Math.min(100, quality * 100)));
		if (_encoder == null || _encoderQuality != q)
		{
			_encoder = new JPEGEncoderOptions(q);
			_encoderQuality = q;
		}
		return _encoder;
	}

	function ensureCapacity():Void
	{
		final want = Std.int(Math.max(1, Math.ceil(seconds * fps)));
		if (_ring.length == want)
			return;

		final kept = _ring;
		_ring = [];
		_ring.resize(want);

		// Preserve history when only the duration grew.
		final copy = Std.int(Math.min(_filled, want));
		for (i in 0...copy)
			_ring[i] = kept[(_next - copy + i + kept.length) % kept.length];

		_filled = copy;
		_next = copy % want;
	}

	function set_seconds(value:Float):Float
	{
		seconds = value < 0.5 ? 0.5 : value;
		if (active)
			ensureCapacity();
		return seconds;
	}

	function set_fps(value:Float):Float
	{
		fps = value < 1 ? 1 : value;
		if (active)
			ensureCapacity();
		return fps;
	}
}
