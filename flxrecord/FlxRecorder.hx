package flxrecord;

import flixel.FlxCamera;
import flixel.FlxG;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;

/**
 * Captures the game's rendered frames at a fixed output rate and hands them to a `FrameSink`.
 *
 * Recording is driven by `FlxG.signals.postDraw`, so the captured image is exactly what the
 * player saw this frame — HUD, shaders, camera fades included. The output rate is independent
 * from the game's framerate: a 240 fps game can be recorded at 30 fps without dropping logic.
 */
class FlxRecorder
{
	/**
	 * Frames per second written to the sink.
	 *
	 * Latched by `start()`: the sink is opened with this rate and the sequence is described
	 * by it, so a change during a take applies to the next one.
	 */
	public var fps(default, set):Float = 30;

	/**
	 * Upper bound on the frames written for a single draw when the game falls behind `fps`.
	 * One draw can only produce one new image, so the extra frames are copies of it.
	 */
	public var maxBurstFrames:Int = 8;

	/**
	 * Resolution multiplier applied while copying. `0.5` records at half size, which is the
	 * cheapest way to keep capture cost low at 60 fps.
	 *
	 * Latched by `start()`: the sink is opened with the size derived from this value, so a
	 * change during a take applies to the next one.
	 */
	public var scale(default, set):Float = 1;

	/**
	 * What gets copied. Defaults to the main camera's canvas, i.e. the game without the
	 * debug overlay drawn on top of the stage.
	 */
	public var source:DisplayObject;

	/**
	 * Camera used when `source` is null.
	 */
	public var camera:FlxCamera;

	public var sink(default, null):FrameSink;

	public var recording(default, null):Bool = false;

	/**
	 * How many frames have been handed to the sink so far.
	 */
	public var captured(default, null):Int = 0;

	var _frame:BitmapData;
	var _matrix = new Matrix();
	var _accumulator:Float = 0;
	var _width:Int = 0;
	var _height:Int = 0;
	var _activeFps:Float = 30;
	var _step:Float = 1 / 30;

	public function new(?sink:FrameSink, ?camera:FlxCamera)
	{
		this.sink = sink;
		this.camera = camera;
	}

	/**
	 * Starts capturing. `sink` may be supplied here to swap outputs between takes.
	 */
	public function start(?sink:FrameSink):Void
	{
		if (recording)
			stop();

		if (sink != null)
			this.sink = sink;

		if (this.sink == null)
			throw 'FlxRecorder.start() needs a sink.';

		final target = resolveSource();
		if (target == null)
			throw 'FlxRecorder.start() found nothing to capture.';

		_width = Std.int(Math.max(1, target.width * scale));
		_height = Std.int(Math.max(1, target.height * scale));

		final frame = new BitmapData(_width, _height, false, 0xFF000000);
		_matrix.a = _width / target.width;
		_matrix.d = _height / target.height;

		_activeFps = fps;
		_step = 1 / fps;
		accumulatorReset();
		captured = 0;

		try
		{
			this.sink.open(_width, _height, _activeFps);
			FlxG.signals.postDraw.add(onPostDraw);
			_frame = frame;
			recording = true;
		}
		catch (error:Dynamic)
		{
			frame.dispose();
			throw error;
		}
	}

	/**
	 * Stops capturing and finalizes the sink.
	 */
	public function stop():Void
	{
		if (!recording)
			return;

		recording = false;
		FlxG.signals.postDraw.remove(onPostDraw);

		if (sink != null)
			sink.close();

		if (_frame != null)
		{
			_frame.dispose();
			_frame = null;
		}
	}

	/**
	 * Drops the capture listener without closing the sink.
	 */
	public function destroy():Void
	{
		stop();
		sink = null;
		camera = null;
		source = null;
	}

	/**
	 * Grabs one frame right now, ignoring the output-rate accumulator.
	 */
	public function grab():Void
	{
		if (sink == null || _frame == null)
			return;

		final target = resolveSource();
		if (target == null)
			return;

		_frame.fillRect(_frame.rect, 0xFF000000);
		_frame.draw(target, _matrix);

		sink.write(_frame, captured++);
	}

	/**
	 * Writes a single still through the current sink without starting a recording.
	 */
	public static function screenshot(?camera:FlxCamera):BitmapData
	{
		final cam = camera != null ? camera : FlxG.camera;
		if (cam == null || cam.canvas == null)
			return null;

		final target = cam.canvas;
		final shot = new BitmapData(Std.int(target.width), Std.int(target.height), false, 0xFF000000);
		shot.draw(target);
		return shot;
	}

	function resolveSource():DisplayObject
	{
		if (source != null)
			return source;

		final cam = camera != null ? camera : FlxG.camera;
		return cam != null ? cam.canvas : null;
	}

	function onPostDraw():Void
	{
		if (!recording)
			return;

		_accumulator += FlxG.elapsed;

		var due = 0;
		while (_accumulator >= _step && due < maxBurstFrames)
		{
			_accumulator -= _step;
			due++;
		}

		if (due == 0)
			return;

		// A stall longer than the burst cap is written off rather than padded with a long run
		// of identical frames.
		if (_accumulator >= _step)
			accumulatorReset();

		grab();

		while (--due > 0)
			writeRepeated();
	}

	function writeRepeated():Void
	{
		if (_frame != null && sink != null)
			sink.write(_frame, captured++);
	}

	inline function accumulatorReset():Void
	{
		_accumulator = 0;
	}

	function set_fps(value:Float):Float
	{
		fps = value < 1 ? 1 : value;
		accumulatorReset();
		return fps;
	}

	function set_scale(value:Float):Float
	{
		scale = value <= 0 ? 1 : value;
		return scale;
	}
}
