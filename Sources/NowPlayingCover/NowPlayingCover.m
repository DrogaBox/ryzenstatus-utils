// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

// The cover of the system's Now Playing session, for macOS 15.4 and later.
//
// The media daemon answers only processes it trusts, and the cover is only
// handed to a callback. RyzenStatus loads this library into /usr/bin/perl,
// which the daemon trusts, through DynaLoader, and runs
// ryzenstatus_now_playing_cover as a perl function (see
// NowPlayingCoverReader.swift). The idea of running inside perl comes from
// ungive/mediaremote-adapter; this file is written new and takes no code
// from it.
//
// Output: one JSON line on stdout with the owning app, the song fields used
// to check the cover belongs to the song on screen, and the cover as base64.
// No cover prints a line without "artwork". Nothing here talks to perl.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*RSGetNowPlayingInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*RSGetNowPlayingClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*RSClientGetBundleIdentifier)(id);

static const NSUInteger RSMaximumArtworkBytes = 8 * 1024 * 1024;
// Both questions share one deadline, well inside the app's wait for perl.
static const int64_t RSReplyTimeout = (int64_t)(1.5 * NSEC_PER_SEC);

static NSString *RSText(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static void RSPrint(NSDictionary *reading) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:reading options:0 error:nil];
    if (json == nil) json = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

// Called by perl as an XSUB: the two arguments are perl's interpreter and the
// sub, and neither is used.
__attribute__((visibility("default")))
void ryzenstatus_now_playing_cover(void *interpreter, void *sub) {
    (void)interpreter;
    (void)sub;
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        RSGetNowPlayingInfo getInfo = framework ? (RSGetNowPlayingInfo)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo") : NULL;
        RSGetNowPlayingClient getClient = framework ? (RSGetNowPlayingClient)dlsym(framework, "MRMediaRemoteGetNowPlayingClient") : NULL;
        RSClientGetBundleIdentifier getBundle = framework ? (RSClientGetBundleIdentifier)dlsym(framework, "MRNowPlayingClientGetBundleIdentifier") : NULL;
        if (getInfo == NULL) {
            RSPrint(@{@"error": @"MediaRemote is unavailable"});
            return;
        }
        // `reading` is only touched on this queue: the callbacks run on it,
        // and the copy that is printed is taken on it.
        dispatch_queue_t queue = dispatch_queue_create("com.ryzenstatus.now-playing-cover", DISPATCH_QUEUE_SERIAL);
        NSMutableDictionary *reading = [NSMutableDictionary dictionary];
        dispatch_group_t answers = dispatch_group_create();
        dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, RSReplyTimeout);

        if (getClient != NULL && getBundle != NULL) {
            dispatch_group_enter(answers);
            getClient(queue, ^(id client) {
                CFStringRef bundle = client ? getBundle(client) : NULL;
                if (bundle != NULL) reading[@"bundle"] = [(__bridge NSString *)bundle copy];
                dispatch_group_leave(answers);
            });
        }
        __block BOOL infoAnswered = NO;
        dispatch_group_enter(answers);
        getInfo(queue, ^(CFDictionaryRef raw) {
            NSDictionary *info = (__bridge NSDictionary *)raw;
            NSString *title = RSText(info, @"kMRMediaRemoteNowPlayingInfoTitle");
            NSString *artist = RSText(info, @"kMRMediaRemoteNowPlayingInfoArtist");
            NSString *album = RSText(info, @"kMRMediaRemoteNowPlayingInfoAlbum");
            NSString *mime = RSText(info, @"kMRMediaRemoteNowPlayingInfoArtworkMIMEType");
            if (title) reading[@"title"] = title;
            if (artist) reading[@"artist"] = artist;
            if (album) reading[@"album"] = album;
            if (mime) reading[@"mime"] = mime;
            id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if ([artwork isKindOfClass:[NSData class]] && [artwork length] > 0
                && [artwork length] <= RSMaximumArtworkBytes) {
                reading[@"artwork"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
            }
            infoAnswered = YES;
            dispatch_group_leave(answers);
        });
        dispatch_group_wait(answers, deadline);

        __block NSDictionary *answer = nil;
        dispatch_sync(queue, ^{
            answer = infoAnswered ? [reading copy] : @{@"error": @"MediaRemote did not answer"};
        });
        RSPrint(answer);
    }
}
