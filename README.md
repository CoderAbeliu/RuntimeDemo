公司技术分享时我分享的主题，从runtime 源码中一步步探索类的实现和加载过程，消息发送机制等。 [runtime 源码下载](https://opensource.apple.com/source/objc4/objc4-723/)
### Runtime-源码分析

> 1.类的初始化 在外部是如何实现的？
> 2.初始化过程中runtime 起到了什么作用？

##### 类的结构体
类是继承于对象的：
```ObjectiveC
struct objc_class : objc_object {
    // Class ISA;
    Class superclass;
    cache_t cache;             // formerly cache pointer and vtable
    class_data_bits_t bits;    // class_rw_t * plus custom rr/alloc flags

    class_rw_t *data() { 
        return bits.data();
    }
......
 }
 ```
 在`objc_class`中有定义了三个变量 ，`superclass` 是一个objc_class的结构体，指向的本类的父类的`objc_class`结构体。`cache `用来处理已经调用方法的缓存。 `class_data_bits_t` 是objc_class 的关键，很多变量都是根据 `bits`来实现的。
 
##### 对象的初始化
在对象初始化的时候，一般都会调用 alloc+init 方法进行实例化，或者通过new 方法。

---
    - 第一步：调用系统的alloc 方法 或者new 方法(其中`new`方法直接调用的`callAlloc init`)
```ObjectiveC
+ (instancetype)alloc OBJC_SWIFT_UNAVAILABLE("use object initializers instead");

+(id)alloc{
    return _objc_rootAlloc(self);
}
```
- 第二步： runtime 内部实现调用objc_rootAlloc 方法
```ObjectiveC
// Base class implementation of +alloc. cls is not nil.
// Calls [cls allocWithZone:nil].
id
_objc_rootAlloc(Class cls)
{
    return callAlloc(cls, false/*checkNil*/, true/*allocWithZone*/);
}
```

---
- 第三步： callAlloc 方法实现，解析：
callAlloc 方法在创建对象的地方有两种方式，一种是通过` calloc` 开辟内存，然后通过`obj->initInstanceIsa(cls, dtor)` 函数初始化这块内存。 第二种是直接调`class_createInstance` 函数，由内部实现初始化逻辑 ;
```ObjectiveC
static ALWAYS_INLINE id
    callAlloc(Class cls, bool checkNil, bool allocWithZone=false) {
    if (fastpath(cls->canAllocFast())) {
    bool dtor = cls->hasCxxDtor();
    id obj = (id)calloc(1, cls->bits.fastInstanceSize()); 
    if (slowpath(!obj)) return callBadAllocHandler(cls); 
    obj->initInstanceIsa(cls, dtor);
    return obj;
    } else {
    id obj = class_createInstance(cls, 0);
    if (slowpath(!obj)) return callBadAllocHandler(cls); return obj;
  }
}
```
但是在最新的` objc-723` 中，调用`canAllocFast()` 函数直接返回false ，所以只会执行上面所述的第二个`else` 代码块。
```ObjectiveC
bool canAllocFast(){
    return false;
}
```
初始化的代码最终会调用到 `_class_createInstanceFromZone` 函数，这个函数是初始化的关键代码。然后通过instanceSize 函数返回的 `size`,并通过`calloc` 函数分配内存，初始化`isa_t` 指针。
```ObjectiveC
size_t size = cls->instanceSize(extraBytes);
obj->initIsa(cls);
```
---
##### 消息的发送机制
在OC 中方法调用时通过Runtime 来实现的，runtime 进行方法调用本质上是发送消息，通过`objc_msgSend()`函数来进行消息的发送 
`[MyClass classMethod]` 在runtime运行时被转换为 `((void ()(id, SEL))(void )objc_msgSend)((id)objc_getClass("MyClass"), sel_registerName("classMethod"));` 

上述的方法可以理解为 向一个objc_class发送了一个SEL 。

OC中每一个`Method` 的结构体如下：
```ObjectiveC
struct objc_method {
    SEL _Nonnull method_name                    
    char * _Nullable method_types              
    IMP _Nonnull method_imp                                 
}
```
在新的`objc_runtime_new.h`中`objc_method`已经没有使用了，使用的是如下的结构体,其引入的方式也发生了改变，不是直接定义在`objc_class`类中，而是通过`getLoadMethod`方法来实现间接的调用。
```ObjectiveC
struct method_t {
    SEL name;
    const char *types;
    IMP imp;

    struct SortBySELAddress :
        public std::binary_function<const method_t&,
                                    const method_t&, bool>
    {
        bool operator() (const method_t& lhs,
                         const method_t& rhs)
        { return lhs.name < rhs.name; }
    };
};
```
`objc_msgSend` 就是通过`SEL` 来进行遍历查找的，如果两个类定义了相同名称的方法，它们的`SEL` 就是一样的。

`objc_method` 中具体参数解析如下：
- `SEL` 指的就是第一步中解析方法调用得到的 `sel_registerName(“methodName”)`的返回值。
- `method_types` 指的是返回值的类型和参数。以返回值为开始，依次把参数拼接在后面，类型对应表格链接[TYPE EDCODING]。(联想一哈，这个东西也是类似于property_gerAttrubute一样，有对应的类型关系，某个字符意味着某种类型) 
- `IMP_Method` 参数 是一个函数指针，指向objc_method所对应的实现部分。

###### objc_msgSend 工作原理

当一个对象被创建，系统会为通过上述的`callalloc` 函数分配一个内存`size` 并给他初始化一个`isa` 指针，可以通过指针访问其类对象，并且通过对类对象访问其所有继承者链中的类。

1. objc_msgSend 底层实现没有完全的暴露出来，但是通过源码中的`objc-msg-simulator-x86_64.s`的第672行代码开始可以看到部分实现，也可以通过`Xcode`断点来查看运行的堆栈信息。其实现原理主要是通过2个方法来完成,首先是`CacheLookup`方法，在缓存中没有存在的情况下会去执行 `__objc_msgSend_uncached` 的 `MethodTable`查找`SEL`

   ```objective-c
   	GetIsaCheckNil NORMAL		// r10 = self->isa, or return zero
   	CacheLookup NORMAL, CALL	// calls IMP on success
   
   	GetIsaSupport NORMAL
   	NilTestReturnZero NORMAL
   
   // cache miss: go search the method lists
   LCacheMiss:
   	// isa still in r10
   	MESSENGER_END_SLOW
   	jmp	__objc_msgSend_uncached
   
   	END_ENTRY _objc_msgSend
   ```

   `__objc_msgSend_uncached` 方法查找

   ```objective-c
   	STATIC_ENTRY __objc_msgSend_uncached
   	UNWIND __objc_msgSend_uncached, FrameWithNoSaves
   
   	// THIS IS NOT A CALLABLE C FUNCTION
   	// Out-of-band x16 is the class to search
   	
   	MethodTableLookup
   	br	x17
   
   	END_ENTRY __objc_msgSend_uncached
   
   
   	STATIC_ENTRY __objc_msgLookup_uncached
   	UNWIND __objc_msgLookup_uncached, FrameWithNoSaves
   
   	// THIS IS NOT A CALLABLE C FUNCTION
   	// Out-of-band x16 is the class to search
   	
   	MethodTableLookup
   	ret
   ```

2. 在执行`MethodTableLookup`方法时其中调用到了`__class_lookupMethodAndLoadCache3` 去找到需要的`Class`参数和`SEL`,内部实现找`IMP` 的是操作 方法是`lookUpImpOrForward`。
2. 当对象接受到消息时，runtime会沿着消息函数的`isa`查找对应的类对象，然后是先在`objc_cache`中去查找当前的`SEL` 的缓存，如果缓存中存在`SEL`，就直接返回该`IMP`也就是该实现方法的指针。

3. 如果cache 中不存在缓存，需要先判断该类是否已经被创建，如果没有，则将类实例化，第一次调用当前类的话，执行`initialized` 代码，再开始读取这个类的缓存，还是没有的情况下才在method list 中查找方法selector。本类如果没有，就会到父类的method list中去查找缓存和method list 中的`SEL`，直到`NSObject`类 。
```ObjectiveC
//如果缓存在就直接返回
 if (cache) {
        imp = cache_getImp(cls, sel);
        if (imp) return imp;
    }
 runtimeLock.read();
// 看看类有没有被初始化，没有初始化就直接初始化
    if (!cls->isRealized()) {
        // Drop the read-lock and acquire the write-lock.
        // realizeClass() checks isRealized() again to prevent
        // a race while the lock is down.
        runtimeLock.unlockRead();
        runtimeLock.write();

        realizeClass(cls);

        runtimeLock.unlockWrite();
        runtimeLock.read();
    }
   //走一遍 initialized 方法
 if (initialize  &&  !cls->isInitialized()) {
        runtimeLock.unlockRead();
        _class_initialize (_class_getNonMetaClass(cls, inst));
        runtimeLock.read();
        // If sel == initialize, _class_initialize will send +initialize and 
        // then the messenger will send +initialize again after this 
        // procedure finishes. Of course, if this is not being called 
        // from the messenger then it won't happen. 2778172
    }
 retry:    
    runtimeLock.assertReading();
```
4.如果在类的继承体系中都没有找到`SEL`,则会进行动态消息解析，给自己保留处理找不到方法的机会，
```ObjectiveC
// 没有找到该方法，会执行下面的分解方法
    if (resolver  &&  !triedResolver) {
        runtimeLock.unlockRead();
        _class_resolveMethod(cls, sel, inst);
        runtimeLock.read();
        // Don't cache the result; we don't hold the lock so it may have 
        // changed already. Re-do the search from scratch instead.
        triedResolver = YES;
        goto retry;
    }
```

其中`_class_resolveMethod` 的源码解析为：
    
```ObjectiveC
if(！cls->isMetaClass()){
   _class_resolveInstanceMethod(cls, sel, inst);
}else{
    _class_resolveClassMethod(cls, sel, inst);
     if (!lookUpImpOrNil(cls, sel, inst, 
                            NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
        {
            _class_resolveInstanceMethod(cls, sel, inst);
        }
}
```
5. 动态消息解析如果没有做出响应，则进入动态消息转发阶段,如果还没有人响应，就会触发`doesNotRecognizeSelector` 此时可以在动态消息转发阶段做一些处理，否则就会`Crash`.
