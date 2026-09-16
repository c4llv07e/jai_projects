SDL_Vulkan_CreateSurface :: (window: *SDL_Window, instance: VkInstance, allocator: *VkAllocationCallbacks, surface: *VkSurfaceKHR) -> bool #foreign sdl3;
SDL_Vulkan_GetInstanceExtensions :: (count: *u32) -> **u8 #foreign sdl3;
SDL_Vulkan_GetVkGetInstanceProcAddr :: () -> PFN_vkGetInstanceProcAddr #foreign sdl3;
SDL_Vulkan_LoadLibrary :: (path: *u8) -> bool #foreign sdl3;

vk_debug_utils_callback :: (messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageType: VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: *VkDebugUtilsMessengerCallbackDataEXT, pUserData: *void) -> VkBool32 #c_call {
        /* Not sure if this will work, need testing with vkSubmitDebugUtilsMessageEXT */
        push_context <<(cast(*#Context) pUserData) {
                print("validation layer: %\n", to_string(pCallbackData.pMessage));
        }
        return VK_FALSE;
}

create_debug_utils_messenger_ext : PFN_vkCreateDebugUtilsMessengerEXT;

get_extensions :: () -> []*u8 {
        sdl_extension_count: u32 = 0;
        sdl_extensions := SDL_Vulkan_GetInstanceExtensions(*sdl_extension_count);
        if sdl_extensions == null {
                print("Can't get sdl required vulkan extensions: %\n", sdl_get_error());
                exit(-1);
        }
        extensions : []*u8;
        extensions.count = sdl_extension_count;
        extensions.data = sdl_extensions;
        return extensions;
}

get_physical_devices :: (vk_instance: VkInstance) -> []VkPhysicalDevice {
        count : u32 = 0;
        result := vkEnumeratePhysicalDevices(vk_instance, *count, null);
        if result != .SUCCESS {
                print("Can't enumerate physical devices!\n");
                exit(-1);
        }
        memory : *VkPhysicalDevice = alloc(size_of(VkPhysicalDevice) * count);
        result = vkEnumeratePhysicalDevices(vk_instance, *count, memory);
        if result != .SUCCESS {
                print("Can't enumerate % physical devices!\n", count);
                exit(-1);
        }
        devices: []VkPhysicalDevice;
        devices.count = count;
        devices.data = memory;
        return devices;
}

get_available_layers :: () -> []VkLayerProperties {
        count: u32 = 0;
        if vkEnumerateInstanceLayerProperties(*count, null) != .SUCCESS {
                print("Can't enumerate available instance layers!\n");
                exit(-1);
        }
        memory : *VkLayerProperties = alloc(size_of(VkLayerProperties) * count);
        if memory == null {
                print("Can't allocate memory for layer properties!\n");
                exit(-1);
        }
        if vkEnumerateInstanceLayerProperties(*count, memory) != .SUCCESS {
                print("Can't get all available layers!\n");
                exit(-1);
        }
        layers: []VkLayerProperties;
        layers.count = count;
        layers.data = memory;
        return layers;
}

main :: () {
        ctx := Ctx.{};
        if !SDL_Init(SDL_INIT_VIDEO) {
                print("Can't init SDL3\n");
                exit(-1);
        }
        if !TTF_Init() {
                print("Can't init SDL3_ttf\n");
                exit(-1);
        }
        ctx.font = TTF_OpenFont(font_path, 24);
        if ctx.font == null {
                print("Can't open font at %!\n", font_path);
                exit(-1);
        }
        window_flags :: SDL_WindowFlags.VULKAN | SDL_WindowFlags.RESIZABLE;
        ctx.window = SDL_CreateWindow("test", 800, 600, window_flags);
        if ctx.window == null {
                print("Can't create window: %!\n", sdl_get_error());
                exit(-1);
        }
        extensions : [..]*u8;
        array_copy(*extensions, get_extensions());
        array_add(*extensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        print("Extensions count: %\n", extensions.count);
        for extensions {
                print("  Extension(%) %\n", it_index, to_string(it));
        }
        available_layers := get_available_layers();
        print("layers: %\n", available_layers.count);
        found_validation_layer := false;
        for available_layers {
                print("layer %\n", to_string(it.layerName.data));
                if to_string(it.layerName.data) == "VK_LAYER_KHRONOS_validation" {
                        found_validation_layer = true;
                        break;
                }
        }
        if !found_validation_layer {
                print("No validation layer found!\n");
                exit(-1);
        }
        vk_app_info := VkApplicationInfo.{
                pApplicationName = "V for vulkan",
                applicationVersion = VK_MAKE_VERSION(1, 0, 0),
                pEngineName = "No Engine",
                engineVersion = VK_MAKE_VERSION(1, 0, 0),
                apiVersion = VK_MAKE_API_VERSION(0, 1, 3, 0),
        };
        vk_debug_utils_messenger_create_info_ext := VkDebugUtilsMessengerCreateInfoEXT.{
                messageSeverity = .VERBOSE_BIT_EXT | .WARNING_BIT_EXT | .ERROR_BIT_EXT,
                messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT | .PERFORMANCE_BIT_EXT,
                pfnUserCallback = vk_debug_utils_callback,
                pUserData = *context,
        };
        vk_instance_create_info := VkInstanceCreateInfo.{
                pNext = *vk_debug_utils_messenger_create_info_ext,
                pApplicationInfo = *vk_app_info,
                enabledExtensionCount = cast(u32) extensions.count,
                ppEnabledExtensionNames = extensions.data,
                enabledLayerCount = 1,
                ppEnabledLayerNames = ((*u8).["VK_LAYER_KHRONOS_validation"]).data,
        };
        vk_instance : VkInstance;
        if vkCreateInstance(*vk_instance_create_info, null, *vk_instance) != .SUCCESS {
                print("Can't create vulkan instance!\n");
                exit(-1);
        }
        vk_debug_messenger : VkDebugUtilsMessengerEXT = VK_NULL_HANDLE;
        create_debug_utils_messenger_ext = cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(vk_instance, "vkCreateDebugUtilsMessengerEXT");
        create_debug_utils_messenger_ext(vk_instance, *vk_debug_utils_messenger_create_info_ext, null, *vk_debug_messenger);
        vk_surface : VkSurfaceKHR;
        if !SDL_Vulkan_CreateSurface(ctx.window, vk_instance, null, *vk_surface) {
                print("Can't create SDL surface for vulkan!\n");
                exit(-1);
        }
        devices := get_physical_devices(vk_instance);
        physical_device: *VkPhysicalDevice = VK_NULL_HANDLE;
        graphics_queue: u32 = cast,no_check(u32)-1;
        for device, device_ind: devices {
                print("Device %: %\n", device_ind, device);
                device_property: VkPhysicalDeviceProperties;
                vkGetPhysicalDeviceProperties(device, *device_property);
                print("device name: %\n", to_string(device_property.deviceName.data));
                queue_family_count: u32 = 0;
                vkGetPhysicalDeviceQueueFamilyProperties(device, *queue_family_count, null);
                if queue_family_count == 0 {
                        print("Can't get queues of device %\n", device_ind);
                        continue;
                }
                queue_families : *VkQueueFamilyProperties = alloc(size_of(VkQueueFamilyProperties) * queue_family_count);
                if queue_families == null {
                        print("Can't allocate memory for queue families!\n");
                        exit(-1);
                }
                vkGetPhysicalDeviceQueueFamilyProperties(device, *queue_family_count, queue_families);
                print("  queues %\n", queue_family_count);
                for queue_ind: 0..queue_family_count - 1 {
                        presentSupport := VK_FALSE;
                        vkGetPhysicalDeviceSurfaceSupportKHR(device, queue_ind, vk_surface, *presentSupport);
                        if queue_families[queue_ind].queueFlags & .GRAPHICS_BIT && presentSupport {
                                physical_device = *device;
                                graphics_queue = queue_ind;
                                break device;
                        }
                }
                free(queue_families);
        }
        if physical_device == VK_NULL_HANDLE {
                print("Can't find supported GPU!\n");
                exit(-1);
        }
        queuePriority: float32 = 1.0;
        queue_create_info := VkDeviceQueueCreateInfo.{
                queueFamilyIndex = graphics_queue,
                queueCount = 1,
                pQueuePriorities = *queuePriority,
        };
        dynamic_rendering_features := VkPhysicalDeviceDynamicRenderingFeatures.{
                dynamicRendering = VK_TRUE,
        };
        device_extensions: []*u8 = .[ VK_KHR_SWAPCHAIN_EXTENSION_NAME ];
        running := true;
        exit(0);
        while (running) {
                event : SDL_Event;
                while (SDL_PollEvent(*event)) {
                        if event.type == {
                                case SDL_EVENT_QUIT;
                                running = false;
                                exit(0);
                        }
                }
        }
        exit(0);
}
