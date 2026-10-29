package flxrecord;

import flxrecord.sinks.SequenceSink;
import sys.FileSystem;
import sys.io.File;

/**
 * Turns a captured sequence into a video, using an ffmpeg binary if one is available.
 *
 * No hidden dependency: when ffmpeg is missing every call reports `false` and the frames
 * stay on disk, which is still a usable result.
 */
class VideoExport
{
	/**
	 * Binary name or absolute path. Override it when ffmpeg is not on `PATH`.
	 */
	public static var ffmpegPath:String = 'ffmpeg';

	static var _available:Null<Bool> = null;

	/**
	 * Whether `ffmpegPath` can be executed. The result is cached for the session.
	 */
	public static function available(?refresh:Bool = false):Bool
	{
		if (_available != null && !refresh)
			return _available;

		_available = run(quote(ffmpegPath) + ' -version' + silence()) == 0;
		return _available;
	}

	/**
	 * Muxes `sink`'s frames together with an audio file.
	 *
	 * @param	sink	The sink that produced the frames; its manifest supplies fps and size.
	 * @param	audio	Optional audio track. Video-only output is produced when omitted.
	 * @param	out		Output path. Defaults to `<dir>/video.mp4`.
	 * @return	`true` only when ffmpeg actually produced the file.
	 */
	public static function mux(sink:SequenceSink, ?audio:String, ?out:String):Bool
	{
		if (sink == null || !available())
			return false;

		final target = out != null ? out : sink.dir + '/video.mp4';
		final audioTrack = audio != null ? audio : sink.audioPath;
		final hasAudio = audioTrack != null && FileSystem.exists(audioTrack);

		final args = new StringBuf();
		args.add('-y -framerate ' + manifestFps(sink));
		args.add(' -i ' + quote(sink.inputPattern()));

		if (hasAudio)
			args.add(' -i ' + quote(audioTrack));

		args.add(' -c:v libx264 -pix_fmt yuv420p -preset veryfast');

		if (hasAudio)
			args.add(' -c:a aac -shortest');

		args.add(' ' + quote(target));

		if (run(quote(ffmpegPath) + ' ' + args.toString() + silence()) != 0)
			return false;

		return FileSystem.exists(target);
	}

	/**
	 * Reads `manifest.json` from a recording folder so a sequence can be muxed later,
	 * in another process, without the original sink instance.
	 */
	public static function muxFolder(dir:String, ?audio:String, ?out:String):Bool
	{
		if (!FileSystem.exists(dir + '/manifest.json'))
			return false;

		final data:Dynamic = try
		{
			haxe.Json.parse(File.getContent(dir + '/manifest.json'));
		}
		catch (e:Dynamic)
		{
			null;
		};

		if (data == null || data.fps == null)
			return false;

		if (data.audio != null && audio == null)
			audio = data.audio;

		if (!available())
			return false;

		final target = out != null ? out : dir + '/video.mp4';
		final input = dir + '/frame_%05d.' + (data.format != null ? data.format : 'jpg');

		final args = new StringBuf();
		args.add('-y -framerate ' + data.fps);
		args.add(' -i ' + quote(input));

		if (audio != null && FileSystem.exists(audio))
			args.add(' -i ' + quote(audio) + ' -c:a aac -shortest');

		args.add(' -c:v libx264 -pix_fmt yuv420p -preset veryfast ' + quote(target));

		if (run(quote(ffmpegPath) + ' ' + args.toString() + silence()) != 0)
			return false;

		return FileSystem.exists(target);
	}

	static function manifestFps(sink:SequenceSink):Float
	{
		final path = sink.dir + '/manifest.json';
		if (!FileSystem.exists(path))
			return 30;

		try
		{
			return haxe.Json.parse(File.getContent(path)).fps;
		}
		catch (e:Dynamic)
		{
			return 30;
		}
	}

	static function run(command:String):Int
	{
		try
		{
			return Sys.command(command);
		}
		catch (e:Dynamic)
		{
			return -1;
		}
	}

	/**
	 * Runs the command without letting it write to the game console.
	 */
	static function silence():String
	{
		#if windows
		return ' > NUL 2> NUL';
		#else
		return ' > /dev/null 2>&1';
		#end
	}

	inline static function quote(path:String):String
	{
		return '"' + path.split('"').join('') + '"';
	}
}
