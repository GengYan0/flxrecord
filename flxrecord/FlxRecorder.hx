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
	 */
	public var fps(default, set):Float = 30;

	/**
	 * Resolution multiplier applied while copying. `0.5` records at half size, which is the
	 * cheapest way to keep capture cost low at 60 fps.
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

		_frame = new BitmapData(_width, _height, false, 0xFF000000);
		_matrix.a = _width / target.width;
		_matrix.d = _height / target.height;

		accumulatorReset();
		captured = 0;
		recording = true;

		this.sink.open(_width, _height, fps);
		FlxG.signals.postDraw.add(onPostDraw);
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
		final target:DisplayObject = camera != null ? camera.canvas : FlxG.camera.canvas;
		if (target == null)
			return null;

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

		final step = 1 / fps;
		_accumulator += FlxG.elapsed;

		if (_accumulator < step)
			return;

		// Never catch up with a burst after a hitch: the recording clock stays real-time,
		// the frozen moment is simply shorter.
		_accumulator -= step;
		if (_accumulator > step)
			accumulatorReset();

		grab();
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
