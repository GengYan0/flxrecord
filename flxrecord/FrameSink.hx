package flxrecord;

import openfl.display.BitmapData;

/**
 * Where captured frames go.
 *
 * A sink is called on the main thread with the recorder's own scratch `BitmapData`. The same
 * instance is overwritten by the next frame, so a sink that wants to keep pixels has to
 * `clone()` them or encode them before returning.
 */
interface FrameSink
{
	/**
	 * Called once before the first frame, with the size of every following frame.
	 */
	public function open(width:Int, height:Int, fps:Float):Void;

	/**
	 * One captured frame. Frames arrive at the recorder's output rate, not the game's.
	 */
	public function write(frame:BitmapData, index:Int):Void;

	/**
	 * Called after the last frame; flush files, close handles, mux tracks.
	 */
	public function close():Void;
}
