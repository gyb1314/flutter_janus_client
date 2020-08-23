import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:janus_client/Plugin.dart';
import 'package:janus_client/janus_client.dart';
import 'package:janus_client/utils.dart';
//import 'package:wakelock/wakelock.dart';

void main() {
  // 强制横屏
  WidgetsFlutterBinding.ensureInitialized();
  // 强制不息屏
//  Wakelock.enable();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]).then((onVal) {
    runApp(MyApp());
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

final _localRenderer = new RTCVideoRenderer();
final _remoteRenderer = new RTCVideoRenderer();

class _MyAppState extends State<MyApp> {
  JanusClient j;
  Plugin pluginHandle;
  Plugin subscriberHandle;
  MediaStream remoteStream;
  MediaStream myStream;
  @override
  void didChangeDependencies() async {
    // TODO: implement didChangeDependencies
    super.didChangeDependencies();
  }

  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await this.initPlatformState();
  }

  _newRemoteFeed(JanusClient j, feed) async {
    print('remote plugin attached');
    j.attach(Plugin(
        plugin: 'janus.plugin.videoroom',
        onMessage: (msg, jsep) async {
          if (jsep != null) {
            await subscriberHandle.handleRemoteJsep(jsep);
            var body = {"request": "start", "room": 1234};

            await subscriberHandle.send(
                message: body,
                jsep: await subscriberHandle.createAnswer(),
                onSuccess: () {});
          }
        },
        onSuccess: (plugin) {
          setState(() {
            subscriberHandle = plugin;
          });
          var register = {
            "request": "join",
            "room": 1234,
            "ptype": "subscriber",
            "feed": feed,
//            "private_id": 12535
          };
          subscriberHandle.send(message: register, onSuccess: () async {});
        },
        onRemoteStream: (stream) {
          print('got remote stream');
          setState(() {
            remoteStream = stream;
            _remoteRenderer.srcObject = remoteStream;
            _remoteRenderer.mirror = true;
          });
        }));
  }

  Future<void> pushLocalStream() async{
    setState(() {
      var register = {
        "request": "join",
        "room": 1234,
        "ptype": "publisher",
        "display": 'shivansh'
      };
      pluginHandle.send(
          message: register,
          onSuccess: () async {
            var publish = {
              "request": "configure",
              "audio": false,
              "video": false,
              "bitrate": 2000000
            };
            RTCSessionDescription offer = await pluginHandle.createOffer();
            pluginHandle.send(
                message: publish, jsep: offer, onSuccess: () {});
          });
    });
  }

  Future<void> initPlatformState() async {
    setState(() {
      j = JanusClient(iceServers: [
        RTCIceServer(
            url: "stun:139.9.39.212:3478",
            username: "gyb1",
            credential: "abc123456"),
        RTCIceServer(
            url: "turn:139.9.39.212:3478",
            username: "gyb1",
            credential: "abc123456")
      ], server: [
        // 'wss://janus.onemandev.tech/websocket',
        'ws://stream.slaman.cn:8188'
      ], withCredentials: true, apiSecret: "SecureIt");
      j.connect(onSuccess: () async {
        debugPrint('voilla! connection established');
        Map<String, dynamic> configuration = {
          "iceServers": j.iceServers.map((e) => e.toMap()).toList()
        };

        j.attach(Plugin(
            plugin: 'janus.plugin.videoroom',
            onMessage: (msg, jsep) async {
              print('publisheronmsg');
              if (msg["publishers"] != null) {
                var list = msg["publishers"];
                print('got publihers');
                print(list);
                _newRemoteFeed(j, list[0]["id"]);
              }

              if (jsep != null) {
                pluginHandle.handleRemoteJsep(jsep);
              }
            },
            onSuccess: (plugin) async {
              setState(() {
                pluginHandle = plugin;
              });
              MediaStream stream = await plugin.initializeMediaDevices();
              setState(() {
                myStream = stream;
              });
              setState(() {
                _localRenderer.srcObject = myStream;
                _localRenderer.mirror = true;
              });
            }));
      }, onError: (e) {
        debugPrint('some error occured');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
                icon: Icon(
                  Icons.call,
                  color: Colors.greenAccent,
                ),
                onPressed: () async {
                  await this.pushLocalStream();
//                  -_localRenderer.
                }),
            IconButton(
                icon: Icon(
                  Icons.call_end,
                  color: Colors.red,
                ),
                onPressed: () {
                  pluginHandle.hangup();
                  subscriberHandle.hangup();
                  _localRenderer.srcObject = null;
                  _localRenderer.dispose();
                  _remoteRenderer.srcObject = null;
                  _remoteRenderer.dispose();
                  setState(() {
                    pluginHandle = null;
                    subscriberHandle = null;
                  });
                }),
            IconButton(
                icon: Icon(
                  Icons.switch_camera,
                  color: Colors.white,
                ),
                onPressed: () {
                  if (pluginHandle != null) {
                    pluginHandle.switchCamera();
                  }
                })
          ],
          title: const Text('janus_client'),
        ),
        body: Stack(children: [
          Positioned.fill(
            child: RTCVideoView(
              _remoteRenderer,
            ),
          ),
          Align(
            child: Container(
              child: RTCVideoView(
                _localRenderer,
              ),
              height: 200,
              width: 200,
            ),
            alignment: Alignment.bottomRight,
          )
        ]),
      ),
    );
  }
}
