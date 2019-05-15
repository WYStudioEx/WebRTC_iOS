//
//  WebRTCHelper.m
//  WebScoketTest
//
//  Created by 涂耀辉 on 17/3/1.
//  Copyright © 2017年 涂耀辉. All rights reserved.
//

//  WebRTCHelper.m
//  WebRTCDemo
//


#import "WebRTCHelper.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

//google提供的
static NSString *const RTCSTUNServerURL = @"stun:stun.l.google.com:19302";
static NSString *const RTCSTUNServerURL2 = @"stun:23.21.150.121";

typedef enum : NSUInteger {
    //发送者
    RoleCaller,
    //被发送者
    RoleCallee,
} Role;

@interface WebRTCHelper ()<SRWebSocketDelegate, RTCPeerConnectionDelegate, RTCSessionDescriptionDelegate>

@end

@implementation WebRTCHelper
{
    SRWebSocket *_socket;
    NSString *_server;
    NSString *_room;
    
    RTCPeerConnectionFactory *_factory;
    RTCMediaStream *_localStream;
    
    NSString *_myId;                       //自己的id
    NSMutableDictionary *_connectionDic;
    NSMutableArray *_connectionIdArray;     //聊天室其他人的id
    
    Role _role;
}

static WebRTCHelper *instance = nil;

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[[self class] alloc] init];
        [instance initData];
        
    });
    return instance;
}

- (void)initData
{
    _connectionDic = [NSMutableDictionary dictionary];
    _connectionIdArray = [NSMutableArray array];
}

/**
 *  与服务器建立连接
 *
 *  @param server 服务器地址
 *  @param room   房间号
 */

//初始化socket并且连接
- (void)connectServer:(NSString *)server port:(NSString *)port room:(NSString *)room
{
    _server = server;
    _room = room;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://%@:%@",server,port]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    _socket = [[SRWebSocket alloc] initWithURLRequest:request];
    _socket.delegate = self;
    [_socket open];
}

/**
 *  加入房间
 *
 *  @param room 房间号
 */
- (void)joinRoom:(NSString *)room
{
    //如果socket是打开状态
    if (_socket.readyState == SR_OPEN)
    {
        //初始化加入房间的类型参数 room房间号
        NSDictionary *dic = @{@"eventName": @"__join", @"data": @{@"room": room}};
        
        //得到json的data
        NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
        //发送加入房间的数据
        [_socket send:data];
    }
}
/**
 *  退出房间
 */
- (void)exitRoom
{
    _localStream = nil;
    [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self closePeerConnection:obj];
    }];
    [_socket close];
}

/**
 *  关闭peerConnection
 *
 *  @param connectionId connectionId description
 */
- (void)closePeerConnection:(NSString *)connectionId
{
    RTCPeerConnection *peerConnection = [_connectionDic objectForKey:connectionId];
    if (peerConnection)
    {
        [peerConnection close];
    }
    [_connectionIdArray removeObject:connectionId];
    [_connectionDic removeObjectForKey:connectionId];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:closeWithUserId:)])
        {
            [_delegate webRTCHelper:self closeWithUserId:connectionId];
        }
    });
}
/**
 *  创建本地流，并且把本地流回调出去
 */
- (void)createLocalStream
{
    _localStream = [_factory mediaStreamWithLabel:@"ARDAMS"];
    //音频
    RTCAudioTrack *audioTrack = [_factory audioTrackWithID:@"ARDAMSa0"];
    [_localStream addAudioTrack:audioTrack];
    
    //视频
    NSArray *deviceArray = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *device = [deviceArray lastObject];
    //检测摄像头权限
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied)
    {
        NSLog(@"相机访问受限");
        if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
        {
            [_delegate webRTCHelper:self setLocalStream:nil userId:_myId];
        }
    }
    else
    {
        if (device)
        {
            RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:device.localizedName];
            RTCVideoSource *videoSource = [_factory videoSourceWithCapturer:capturer constraints:[self localVideoConstraints]];
            RTCVideoTrack *videoTrack = [_factory videoTrackWithID:@"ARDAMSv0" source:videoSource];
            [_localStream addVideoTrack:videoTrack];
            
            if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
            {
                [_delegate webRTCHelper:self setLocalStream:_localStream userId:_myId];
            }
        }
        else
        {
            NSLog(@"该设备不能打开摄像头");
            if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:userId:)])
            {
                [_delegate webRTCHelper:self setLocalStream:nil userId:_myId];
            }
        }
    }
}
/**
 *  视频的相关约束
 */
- (RTCMediaConstraints *)localVideoConstraints
{
    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"640"];
    RTCPair *minWidth = [[RTCPair alloc] initWithKey:@"minWidth" value:@"640"];
    
    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"480"];
    RTCPair *minHeight = [[RTCPair alloc] initWithKey:@"minHeight" value:@"480"];
    
    RTCPair *minFrameRate = [[RTCPair alloc] initWithKey:@"minFrameRate" value:@"15"];
    
    NSArray *mandatory = @[maxWidth, minWidth, maxHeight, minHeight, minFrameRate];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
    return constraints;
}
/**
 *  为所有连接创建offer
 */
- (void)createOffers
{
    //给每一个点对点连接，都去创建offer
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        [obj createOfferWithDelegate:self constraints:[self offerOranswerConstraint]];
    }];
}
/**
 *  为所有连接添加流
 */
- (void)addStreams
{
    //给每一个点对点连接，都加上本地流
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        [obj addStream:_localStream];
    }];
}
/**
 *  创建所有连接
 */
- (void)createPeerConnections
{
    //从我们的连接数组里快速遍历
    [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        //根据连接ID去初始化 RTCPeerConnection 连接对象
        RTCPeerConnection *connection = [self createPeerConnection];
        
        //设置这个ID对应的 RTCPeerConnection对象
        [_connectionDic setObject:connection forKey:obj];
    }];
}
/**
 *  创建点对点连接
 *
 *  @return return value description
 */
- (RTCPeerConnection *)createPeerConnection
{
    static NSArray *ICEServers = nil;
    if(ICEServers)
        ICEServers = @[[self defaultSTUNServer:RTCSTUNServerURL], [self defaultSTUNServer:RTCSTUNServerURL2]];
    
    //用工厂来创建连接
    RTCPeerConnection *connection = [_factory peerConnectionWithICEServers:ICEServers constraints:[self peerConnectionConstraints] delegate:self];
    return connection;
}

- (RTCICEServer *)defaultSTUNServer:(NSString *)stunURL {
    NSURL *defaultSTUNServerURL = [NSURL URLWithString:stunURL];
    return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                    username:@""
                                    password:@""];
}

/**
 *  peerConnection约束
 *
 *  @return return value description
 */
- (RTCMediaConstraints *)peerConnectionConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:@[[[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]]];
    return constraints;
}
/**
 *  设置offer/answer的约束
 */
- (RTCMediaConstraints *)offerOranswerConstraint
{
    NSMutableArray *array = [NSMutableArray array];
    RTCPair *receiveAudio = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    [array addObject:receiveAudio];
    
    RTCPair *receiveVideo = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"];
    [array addObject:receiveVideo];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:array optionalConstraints:nil];
    return constraints;
}

#pragma mark--SRWebSocketDelegate
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    NSLog(@"收到服务器消息:%@",message);
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
    NSString *eventName = dic[@"eventName"];
    
    //1.发送加入房间后的反馈，就是自建服务器回包，告诉目前聊天室的情况
    if ([eventName isEqualToString:@"_peers"])
    {
        _role = RoleCaller;
        
        //得到data
        NSDictionary *dataDic = dic[@"data"];
        //得到所有的连接
        NSArray *connections = dataDic[@"connections"];
        //加到连接数组中去
        [_connectionIdArray addObjectsFromArray:connections];
        
        //拿到给自己分配的ID
        _myId = dataDic[@"you"];
        
        //如果为空，则创建点对点工厂
        if (!_factory)
        {
            //设置SSL传输
            [RTCPeerConnectionFactory initializeSSL];
            _factory = [[RTCPeerConnectionFactory alloc] init];
        }
        //如果本地视频流为空
        if (!_localStream)
        {
            //创建本地流
            [self createLocalStream];
        }
        
        //创建连接，去连接聊天室中的其他人
        [self createPeerConnections];
        
        //添加视频流到WebRtc
        [self addStreams];
        
        //创建Offers，给房间里的每个人都发送一个offers
        [self createOffers];
    }
    //2.其他新人加入房间的信息
    else if ([eventName isEqualToString:@"_new_peer"])
    {
        _role = RoleCallee;
        
        NSDictionary *dataDic = dic[@"data"];
        //拿到新人的ID
        NSString *socketId = dataDic[@"socketId"];
        //再去创建一个连接
        RTCPeerConnection *peerConnection = [self createPeerConnection];
        //把本地流加到连接中去
        [peerConnection addStream:_localStream];
        //连接ID新加一个
        [_connectionIdArray addObject:socketId];
        //并且设置到Dic中去
        [_connectionDic setObject:peerConnection forKey:socketId];
    }
    //接收对方（有可能是新进的人，有可能是以前存在的人）发的ICE候选，（即经过ICEServer而获取到的地址）
    else if ([eventName isEqualToString:@"_ice_candidate"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        NSString *sdpMid = dataDic[@"id"];
        NSInteger sdpMLineIndex = [dataDic[@"label"] integerValue];
        NSString *sdp = dataDic[@"candidate"];
        //生成远端网络地址对象
        RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:sdpMid index:sdpMLineIndex sdp:sdp];
        //拿到当前对应的点对点连接
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        //添加到点对点连接中
        [peerConnection addICECandidate:candidate];
    }
    //有人离开房间的事件
    else if ([eventName isEqualToString:@"_remove_peer"])
    {
        //得到socketId，关闭这个peerConnection
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        [self closePeerConnection:socketId];
    }
    //_offer是以前就在房间的人，收到新加入的人发的offer； _answer是新进来的人，收到以前就在房间的人的answer
    else if ([eventName isEqualToString:@"_offer"] || [eventName isEqualToString:@"_answer"])
    {
        NSDictionary *dataDic = dic[@"data"];
        NSDictionary *sdpDic = dataDic[@"sdp"];
        //拿到SDP
        NSString *sdp = sdpDic[@"sdp"];
        NSString *type = sdpDic[@"type"];
        NSString *socketId = dataDic[@"socketId"];
        
        //拿到这个点对点的连接
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        //根据类型和SDP 生成SDP描述对象
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdp];
        //设置给这个点对点连接
        [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
    }
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    NSLog(@"websocket建立成功");
    //加入房间
    [self joinRoom:_room];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)error.code, error.localizedDescription);
    //    [[[UIAlertView alloc] initWithTitle:@"提示" message:[NSString stringWithFormat:@"%ld:%@",(long)error.code, error.localizedDescription] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil, nil] show];
}
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)code, reason);
    //    [[[UIAlertView alloc] initWithTitle:@"提示" message:[NSString stringWithFormat:@"%ld:%@",(long)code, reason] delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil, nil] show];
}

- (NSString *)getKeyFromConnectionDic:(RTCPeerConnection *)peerConnection
{
    //find socketid by pc
    static NSString *socketId;
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        if ([obj isEqual:peerConnection])
        {
            NSLog(@"%@",key);
            socketId = key;
        }
    }];
    return socketId;
}

#pragma mark--RTCSessionDescriptionDelegate
//创建了一个SDP就会被调用，（只能创建本地的， createOfferWithDelegate 或者  createAnswerWithDelegate 之后就是造成这个回调
- (void)peerConnection:(RTCPeerConnection *)peerConnection didCreateSessionDescription:(RTCSessionDescription *)sdp error:(NSError *)error
{
    NSLog(@"%s",__func__);
    NSLog(@"%@",sdp.type);
    
    //设置本地的SDP
    [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
}

//当一个远程或者本地的SDP被设置就会调用
- (void)peerConnection:(RTCPeerConnection *)peerConnection didSetSessionDescriptionWithError:(NSError *)error
{
    NSLog(@"%s",__func__);
    
    NSString *currentId = [self getKeyFromConnectionDic : peerConnection];
    
    //判断，当前连接状态为收到了远程点发来的offer，就调到这里 setRemoteDescriptionWithDelegate 完后会造成这个回调
    if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer)
    {
        //创建一个answer,会把自己的SDP信息返回出去
        [peerConnection createAnswerWithDelegate:self constraints:[self offerOranswerConstraint]];
    }
    //判断连接状态为本地发送offer， setLocalDescriptionWithDelegate完后会造成这个回调
    else if (peerConnection.signalingState == RTCSignalingHaveLocalOffer)
    {
        if (_role == RoleCallee)//感觉这个判断不会调进来
        {
//            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
//            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
//            [_socket send:data];
        }
        else if(_role == RoleCaller) //发送者,发送自己的offer
        {
            NSDictionary *dic = @{@"eventName": @"__offer", @"data": @{@"sdp": @{@"type": @"offer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
    else if (peerConnection.signalingState == RTCSignalingStable) //代表本地跟远程的sdp都有了
    {
        if (_role == RoleCallee)
        {
            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
}

#pragma mark--RTCPeerConnectionDelegate
// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection signalingStateChanged:(RTCSignalingState)stateChanged
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", stateChanged);
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
    
    NSString *uid = [self getKeyFromConnectionDic : peerConnection];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:addRemoteStream:userId:)])
        {
            //[_delegate webRTCHelper:self addRemoteStream:stream userId:_currentId];
            [_delegate webRTCHelper:self addRemoteStream:stream userId:uid];
        }
    });
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream
{
    NSLog(@"%s",__func__);
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    NSLog(@"%s",__func__);
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", newState);
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
   iceGatheringChanged:(RTCICEGatheringState)newState
{
    NSLog(@"%s",__func__);
    NSLog(@"%d", newState);
}

// New Ice candidate have been found.
//创建createPeerConnection之后，从server得到响应后调用，得到ICE 候选地址，发送给服务端
- (void)peerConnection:(RTCPeerConnection *)peerConnection gotICECandidate:(RTCICECandidate *)candidate
{
    NSLog(@"%s",__func__);
    
    NSString *currentId = [self getKeyFromConnectionDic : peerConnection];
    
    NSDictionary *dic = @{@"eventName": @"__ice_candidate", @"data": @{@"id":candidate.sdpMid,@"label": [NSNumber numberWithInteger:candidate.sdpMLineIndex], @"candidate": candidate.sdp, @"socketId": currentId}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
    [_socket send:data];
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection didOpenDataChannel:(RTCDataChannel*)dataChannel
{
    NSLog(@"%s",__func__);
}

@end


//创建连接对象 createPeerConnection 引起创建ICE，并调用 - (void)peerConnection:(RTCPeerConnection *)peerConnection gotICECandidate:(RTCICECandidate *)candidate 发送自己的ICE
//创建SDP对象 createOfferWithDelegate 或者  createAnswerWithDelegate， 引起 didCreateSessionDescription， 并在次设置本地的SDP，而设置本地SDP又引起 didSetSessionDescriptionWithError
//调用，在此发送自己的SDP
