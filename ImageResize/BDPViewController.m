// Copyright (c) 2011 Richard Mazorodze
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "BDPViewController.h"


@implementation BDPViewController

@synthesize imageViewCGContext = imageViewCGContext_;
@synthesize imageViewNeon = imageViewNeon_;

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - Image Resize

static void inline resizeRow(uint32_t *dst, uint32_t *src, uint32_t pixelsPerRow)
{
    const uint32_t * rowB = src + pixelsPerRow;
    
    // force the number of pixels per row to a mutliple of 8
    pixelsPerRow = 8 * (pixelsPerRow / 8);    
    
    __asm__ volatile("Lresizeloop:                      \n" // start loop
                     "vld1.32       {d0-d3}, [%1]!      \n" // load 8 pixels from the top row
                     "vld1.32       {d4-d7}, [%2]!      \n" // load 8 pixels from the bottom row
                     "vhadd.u8      q0, q0, q2          \n" // average the pixels vertically
                     "vhadd.u8      q1, q1, q3          \n"
                     "vtrn.32       q0, q2              \n" // transpose to put the horizontally adjacent pixels in different registers
                     "vtrn.32       q1, q3              \n"
                     "vhadd.u8      q0, q0, q2          \n" // average the pixels horizontally
                     "vhadd.u8      q1, q1, q3          \n"
                     "vtrn.32       d0, d1              \n" // fill the registers with pixels
                     "vtrn.32       d2, d3              \n"
                     "vswp          d1, d2              \n"
                     "vst1.64       {d0-d1}, [%0]!      \n" // store the result
                     "subs          %3, %3, #8          \n" // subtract 8 from the pixel count
                     "bne           Lresizeloop         \n" // repeat until the row is complete
					 : "=r"(dst), "=r"(src), "=r"(rowB), "=r"(pixelsPerRow)
					 : "0"(dst), "1"(src), "2"(rowB), "3"(pixelsPerRow)
					 : "q0", "q1", "q2", "q3", "cc"
					 );
}

static CGContextRef createBitmapContext(void *data, size_t width, size_t height, size_t bytesPerRow, CGImageAlphaInfo alphaInfo)
{	
	CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(data,
												 width,
												 height,
												 8,
												 bytesPerRow,
												 colorspace,
												 alphaInfo);
	CFRelease(colorspace);
	assert(context != NULL);
	return context;
}

- (UIImage *)downscaleImage:(UIImage *)image
{
    // create a bitmap context the right size and draw into it
    size_t width = CGImageGetWidth(image.CGImage) / 2;
    size_t height = CGImageGetHeight(image.CGImage) / 2;
    size_t bytesPerRow = CGImageGetBytesPerRow(image.CGImage) / 2;
    CGImageAlphaInfo imageAlpha = CGImageGetAlphaInfo(image.CGImage);
    CGContextRef ctx = createBitmapContext(NULL, width, height, bytesPerRow, imageAlpha);
    
    CGRect imageRect = CGRectMake(0, 0, width, height);
    CGContextDrawImage(ctx, imageRect, image.CGImage);
    CGImageRef downscaledImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    UIImage *returnImage = [UIImage imageWithCGImage:downscaledImage];
    CGImageRelease(downscaledImage);
    return returnImage;
}

- (UIImage *)downscaleImageNeon:(UIImage *)image
{
    size_t width = CGImageGetWidth(image.CGImage);
    size_t height = CGImageGetHeight(image.CGImage);
    size_t bytesPerRow = CGImageGetBytesPerRow(image.CGImage);
    CGImageAlphaInfo imageAlpha = CGImageGetAlphaInfo(image.CGImage);
    
    // get access to the images pixel buffer
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
    const uint8_t *buffer = CFDataGetBytePtr(data);
    
    // downscale the image in place
    for (size_t rowIndex = 0; rowIndex < height; rowIndex+=2)
    {
        void *sourceRow = (uint8_t *)buffer + rowIndex * bytesPerRow;
        void *destRow = (uint8_t *)buffer + (rowIndex / 2) * bytesPerRow;
        resizeRow(destRow, sourceRow, width);
    }

    // get the output image
    CGContextRef context = createBitmapContext((void *)buffer, width / 2, height / 2, bytesPerRow, imageAlpha);
    CGImageRef scaledImage = CGBitmapContextCreateImage(context);
    UIImage *returnImage = [UIImage imageWithCGImage:scaledImage];
    CGImageRelease(scaledImage);
    CGContextRelease(context);
    CFRelease(data);
    
    return returnImage;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
	// load the image to downscale
    UIImage *image = [UIImage imageNamed:@"lena.png"];
    
    // first downscale using CGContext drawing
    CFAbsoluteTime t = CFAbsoluteTimeGetCurrent();
    UIImage *scaledImage = [self downscaleImage:image];
    t = CFAbsoluteTimeGetCurrent() - t;
    NSLog(@"CGContext downscaling took %f seconds", t);
    self.imageViewCGContext.image = scaledImage;
    
    // then downscale using NEON 
    t = CFAbsoluteTimeGetCurrent();
    UIImage *neonScaledImage = [self downscaleImageNeon:image];
    t = CFAbsoluteTimeGetCurrent() - t;
    NSLog(@"NEON downscaling took %f seconds", t);
    self.imageViewNeon.image = neonScaledImage;
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    // Release any retained subviews of the main view.
    self.imageViewCGContext = nil;
    self.imageViewNeon = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return UIInterfaceOrientationIsPortrait(interfaceOrientation);
}

@end
