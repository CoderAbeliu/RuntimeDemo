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
    SEL sel = NSSelectorFromString(@"testMethod");
    NSObject *obj = [class new];
    NSMethodSignature *methodSign = [obj methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSign];
    [invocation setTarget:obj];
    [invocation setSelector:sel];
    [invocation invoke];
    
    SEL addMethodSel = NSSelectorFromString(@"addNumber");
    NSMethodSignature *signature = [class methodSignatureForSelector:addMethodSel];
    NSInvocation *invocation2 = [NSInvocation invocationWithMethodSignature:signature];
    [invocation2 setTarget:class];
    [invocation2 setSelector:addMethodSel];
    [invocation2 invoke];
    
}


@end
