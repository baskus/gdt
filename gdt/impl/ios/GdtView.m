/*
 * GdtView.m
 *
 * Copyright (c) 2011 Rickard Edström
 * Copyright (c) 2011 Sebastian Ärleryd
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "GdtView.h"
#include "gdt.h"
#include "gdt_ios.h"
#import <OpenGLES/EAGLDrawable.h> 
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <sys/time.h>



touchhandler_t touch_cb = NULL;
int __h;
string_t resourceDir;
string_t storageDir;
string_t cacheDir;

@implementation GdtView


static NSString* logTypeToFormatString(log_type_t type) {
    switch(type) {
        case LOG_ERROR:
            return @"%s: [error] %s";
        case LOG_WARNING:
            return @"%s: [warning] %s";
        case LOG_DEBUG:
            return @"%s: [debug] %s";
        case LOG_NORMAL:
            return @"%s: %s";
    } 
}

void gdt_logv(log_type_t type, string_t tag, string_t format, va_list args) {
    NSString* s = [NSString stringWithFormat:
                       logTypeToFormatString(type), tag, format];
        
    NSLogv(s, args);     
}



void gdt_exit(exit_type_t type) {
    [NSThread exit];
}


void gdt_open_url(string_t url) {
    NSString* s   = [NSString stringWithUTF8String: url];
    NSURL*    u   = [NSURL URLWithString: s];
    
    [[UIApplication sharedApplication] openURL: u];
}



void gdt_set_callback_touch(touchhandler_t f) {
        touch_cb = f;
}
void gdt_set_virtual_keyboard_mode(keyboard_mode_t mode) {
    
}

struct resource {
  int32_t len;
  void*   data;
};

void* gdt_resource_bytes(resource_t res) {
	return res->data;
}

int32_t gdt_resource_length(resource_t res) {
	return res->len;
}


resource_t gdt_resource_load(string_t resourcePath) {
    char* s;
    asprintf(&s, "%s%s", resourceDir, resourcePath);
    
    int fd = open(s, O_RDONLY);
    free(s);
    if (fd == -1) return NULL;
    resource_t res = (resource_t)malloc(sizeof(struct resource));
    struct stat info;
    fstat(fd, &info);
    res->len = info.st_size;
    res->data = mmap(NULL, res->len, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);

    return res;
}

void gdt_resource_unload(resource_t resource) {    
    munmap(gdt_resource_bytes(resource), gdt_resource_length(resource));
    
    free(resource);
}

struct audioplayer {
    AVAudioPlayer* player;
};

audioplayer_t gdt_audioplayer_create(string_t p) {
    NSString* path = [NSString stringWithFormat:@"%s%s", resourceDir, p];
    NSURL* url = [NSURL fileURLWithPath:path];
    
    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:NULL];
    
    if(player == nil)
        return NULL;
        
    [player prepareToPlay];
    
    audioplayer_t ap = (audioplayer_t)malloc(sizeof(struct audioplayer));
    ap->player = player;
    
    return ap;
}

void gdt_audioplayer_destroy(audioplayer_t player) {
    [player->player release];
    free(player);
}

bool gdt_audioplayer_play(audioplayer_t player) {
    [player->player play];
    return true;
}

string_t gdt_get_storage_directory_path(void) {
    return storageDir;
}

string_t gdt_get_cache_directory_path(void) {
    return cacheDir;
}

void gdt_gc_hint(void) {
}

uint64_t gdt_time_ns(void) {
    struct timeval now;
	gettimeofday(&now, NULL);
    return (uint64_t) now.tv_sec * 1000000000LL + (uint64_t) now.tv_usec * 1000LL;
}

-(id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        CAEAGLLayer* layer = (CAEAGLLayer*)super.layer;
        layer.opaque = YES;
        
        ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        [EAGLContext setCurrentContext:ctx];
        
        GLuint fb;
        glGenFramebuffers(1, &fb);
        glBindFramebuffer(GL_FRAMEBUFFER, fb);
        
        GLuint rb;
        glGenRenderbuffers(1, &rb);
        glBindRenderbuffer(GL_RENDERBUFFER, rb);
        
        glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                                     GL_COLOR_ATTACHMENT0,
                                     GL_RENDERBUFFER,
                                     rb);
        
        [ctx renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
        
        resourceDir = [[[NSBundle mainBundle] resourcePath] cStringUsingEncoding:NSASCIIStringEncoding];
        storageDir = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] cStringUsingEncoding:NSASCIIStringEncoding];
        cacheDir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] cStringUsingEncoding:NSASCIIStringEncoding];
        
        gdt_hook_initialize();
        gdt_hook_visible(CGRectGetWidth(frame), __h = CGRectGetHeight(frame));
        
        CADisplayLink* link = [CADisplayLink displayLinkWithTarget:self
                                             selector:@selector(drawView:)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    
    return self;
}

+(Class)layerClass
{
    return [CAEAGLLayer class];
}


-(void)drawView:(CADisplayLink*)_
{
    gdt_hook_render();
    
    [ctx presentRenderbuffer:GL_RENDERBUFFER];
}

-(void)handleTouches:(NSSet*)touches withType:(touch_type_t)type 
{
    if (touch_cb) {
        CGPoint where = [[touches anyObject] locationInView:self];
        touch_cb(type, where.x, __h-where.y);    
    }
}


-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)_
{
    [self handleTouches:touches withType:TOUCH_DOWN];
}

-(void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)_
{
    [self handleTouches:touches withType:TOUCH_MOVE];
}

-(void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)_
{
    [self handleTouches:touches withType:TOUCH_UP];
}


-(void)dealloc
{
    [EAGLContext setCurrentContext:nil];
    [ctx release];
    [super dealloc];
}

@end
