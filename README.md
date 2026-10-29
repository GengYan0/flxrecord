# flxrecord

逐帧录制与即时回放缓冲。把 flixel 画完的每一帧接出来，写成 PNG 序列，或者留住最近 N 秒
随时导出成视频。

## 能力

| 能力 | 入口 |
|---|---|
| 按目标帧率录制 | `FlxRecorder.fps` / `FlxRecorder.scale` |
| 输出到自定义写入端 | `FrameSink` 接口 |
| 内置 PNG/JPEG 序列写入端 | `sinks.SequenceSink` |
| 最近 N 秒环形缓冲 | `FlxReplay(seconds, fps, quality)` |
| 导出为视频 | `VideoExport.mux()` |
| 单帧截图 | `FlxRecorder.screenshot()` |

## 安装

```xml
<haxelib name="flxrecord"/>
```

```bash
haxelib git flxrecord https://github.com/GengYan0/flxrecord
```

依赖 `flixel` 6.2.0、`openfl` 9.5.2、`lime` 8.3.2。`VideoExport` 需要 `PATH` 上有
`ffmpeg`，或者用 `VideoExport.ffmpegPath` 指定。

## 录制一段画面

```haxe
import flxrecord.FlxRecorder;
import flxrecord.sinks.ImageFormat;
import flxrecord.sinks.SequenceSink;

var sink = new SequenceSink('out/rec01', ImageFormat.PNG, 0.9, 'frame_');
var rec = new FlxRecorder(sink);

rec.fps = 30;      // 输出帧率，与游戏帧率无关
rec.scale = 0.5;   // 半分辨率输出
rec.start();

// 需要停的时候
rec.stop();
trace('captured ${rec.captured} frames');
```

`rec.recording` 给出当前状态。`fps` 与 `scale` 在 `start()` 时锁定：写入端的尺寸和帧率是
`open()` 一次给定的，录到一半改这两个值只会影响下一次开录。

`fps` 只决定多久采样一帧：游戏跑 240 fps 时按 30 fps 输出会隔帧取样，逻辑一帧不跳；
游戏掉到 30 fps 以下时同一张画面会被重复写出，序列的时间轴与真实时间对齐，不会因为
卡顿把整段视频压短。单次绘制最多补 `maxBurstFrames` 帧，超过的部分丢弃。

## 合成视频

```haxe
import flxrecord.VideoExport;

if (VideoExport.available())
	VideoExport.mux(sink, 'audio/track.ogg', 'out/rec01.mp4');
```

`mux` 把序列交给 ffmpeg 封装，`audio` 可以给一个音轨。手上有现成的 PNG 目录时用
`VideoExport.muxFolder(dir, audio, out)`。

## 即时回放

`FlxReplay` 一直填环形缓冲，出事时把最近 N 秒吐出来：

```haxe
import flxrecord.FlxReplay;

var replay = new FlxReplay(15, 30, 0.85);   // 15 秒，30 fps，JPEG 质量 0.85

// 接一个录制器把帧灌进来，见下面的「录制一段画面」
var rec = new FlxRecorder(replay);
rec.scale = 0.75;
rec.start();

// 保存成一串图片
var sink = replay.dump('out/replay');

// 或者直接出视频
var path = replay.save('out/replay', 'audio/track.ogg', 'out/replay.mp4');
```

`replay.seconds` 与 `replay.fps` 可以随时改，缓冲会按新尺寸重建。`replay.clear()` 清空。
`dump()` 的第二个参数用来指定音轨，不传则用 `replay.audioPath`。

## 自己写写入端

`sink.write()` 拿到的是录制器自己的暂存 `BitmapData`，下一帧会被覆盖。要留住像素，
在 `write()` 里就地编码，或者 `clone()` 一份再交给别的线程。

```haxe
import flxrecord.FrameSink;
import openfl.display.BitmapData;

class NullSink implements FrameSink
{
	var count = 0;

	public function open(width:Int, height:Int, fps:Float):Void
		count = 0;

	public function write(frame:BitmapData, index:Int):Void
		count++;

	public function close():Void
		trace('$count frames');
}
```

`open` 拿到输出尺寸与帧率，`write` 的 `index` 从 0 递增，`close` 在 `stop()` 时调用。

## 单帧截图

```haxe
var shot = FlxRecorder.screenshot();   // 返回 BitmapData，用完自己 dispose()
if (shot != null)
{
	final png = shot.encode(shot.rect, new PNGEncoderOptions());
	shot.dispose();
	sys.io.File.saveBytes('out/shot.png', cast png);
}
```

不传 `camera` 时截当前主相机，截出来的内容与玩家看到的一致（含 HUD 与着色器效果）。

## 接入时机

`FlxRecorder` 自己订阅 `FlxG.signals.postDraw`，所以只在该录制的状态里构造它即可，
用完 `stop()`。`stop()` 只停采集，录制器还能再 `start()`；彻底不要了调 `destroy()`，
它先 `stop()` 再松开 `sink`/`camera`/`source` 的引用。

空闲时它不采样，开销可以忽略；正在录时每一帧都要拷一份位图并落盘，这部分不能白付。

## 边界

- 输出帧率与游戏帧率解耦，但采样点固定在 `postDraw`，录不到 `postDraw` 之后的改动。
- `SequenceSink` 每帧一个文件，长时间录制会占大量磁盘。同一目录重复录制会覆盖同名帧，
  `manifest.json` 里的 `frames` 只统计本次写入。
- `VideoExport` 只做封装，不做编码参数调优；要控制码率得自己写 ffmpeg 命令行。
- 录制期间 `BitmapData` 拷贝开销随 `scale` 的平方增长。
- `FlxReplay` 存的是 JPEG 字节，缓冲占用只与 `seconds * fps * 单帧大小` 有关。
