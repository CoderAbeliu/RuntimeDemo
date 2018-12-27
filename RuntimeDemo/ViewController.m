//
//  ViewController.m
//  RuntimeDemo
//
//  Created by Abe_liu on 2018/12/27.
//  Copyright © 2018 Abe_liu. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    //此处只是实现了类方法的调用，在进行实例方法的调用时，请注意target 的传参
    Class class = NSClassFromString(@"Test");
    SEL sel = NSSelectorFromString(@"addNumber");
    NSMethodSignature *methodSign = [class methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSign];
    [invocation setTarget:class];
    [invocation setSelector:sel];
    [invocation invoke];
}


@end
