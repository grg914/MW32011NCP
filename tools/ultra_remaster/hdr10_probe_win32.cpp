// Probe Vulkan HDR10 surface support without injecting into any game process.
// Windows x64 only. Uses the vendored Vulkan-Headers via /I and dynamically
// loads vulkan-1.dll, so it does not require a Vulkan SDK binary at runtime.
// A reported HDR10 format does not prove that Windows HDR is enabled or that
// the selected display supports HDR10 presentation at its current mode.
#define VK_USE_PLATFORM_WIN32_KHR
#define VK_NO_PROTOTYPES
#include <windows.h>
#include <vulkan/vulkan.h>
#include <cstdio>
#include <cstring>
#include <vector>
#include <cstdint>

namespace {
template <typename T>
T LoadVk(PFN_vkGetInstanceProcAddr gip, VkInstance instance, const char* name) {
    return reinterpret_cast<T>(gip(instance, name));
}

const char* Name(VkFormat format) {
    switch (format) {
        case VK_FORMAT_A2B10G10R10_UNORM_PACK32: return "A2B10G10R10_UNORM_PACK32";
        case VK_FORMAT_A2R10G10B10_UNORM_PACK32: return "A2R10G10B10_UNORM_PACK32";
        case VK_FORMAT_R16G16B16A16_SFLOAT: return "R16G16B16A16_SFLOAT";
        case VK_FORMAT_B8G8R8A8_UNORM: return "B8G8R8A8_UNORM";
        default: return "other";
    }
}
}

int main() {
    HMODULE loader = LoadLibraryA("vulkan-1.dll");
    if (!loader) {
        std::fprintf(stderr, "vulkan-1.dll unavailable: install a Vulkan-capable graphics driver.\n");
        return 2;
    }

    auto gip = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        GetProcAddress(loader, "vkGetInstanceProcAddr"));
    if (!gip) {
        std::fprintf(stderr, "vkGetInstanceProcAddr missing.\n");
        FreeLibrary(loader);
        return 2;
    }

    auto enumerateExt = LoadVk<PFN_vkEnumerateInstanceExtensionProperties>(
        gip, VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    auto createInstance = LoadVk<PFN_vkCreateInstance>(
        gip, VK_NULL_HANDLE, "vkCreateInstance");
    if (!enumerateExt || !createInstance) {
        std::fprintf(stderr, "Vulkan loader exports missing.\n");
        FreeLibrary(loader);
        return 2;
    }

    uint32_t extensionCount = 0;
    if (enumerateExt(nullptr, &extensionCount, nullptr) != VK_SUCCESS) {
        std::fprintf(stderr, "Unable to enumerate Vulkan instance extensions.\n");
        FreeLibrary(loader);
        return 2;
    }
    std::vector<VkExtensionProperties> extensions(extensionCount);
    if (extensionCount && enumerateExt(nullptr, &extensionCount, extensions.data()) != VK_SUCCESS) {
        std::fprintf(stderr, "Unable to read Vulkan instance extensions.\n");
        FreeLibrary(loader);
        return 2;
    }
    auto hasExtension = [&](const char* extensionName) {
        for (const auto& item : extensions)
            if (std::strcmp(item.extensionName, extensionName) == 0) return true;
        return false;
    };

    if (!hasExtension(VK_KHR_SURFACE_EXTENSION_NAME) ||
        !hasExtension(VK_KHR_WIN32_SURFACE_EXTENSION_NAME)) {
        std::fprintf(stderr, "Vulkan WSI surface extensions not available.\n");
        FreeLibrary(loader);
        return 2;
    }

    const bool hasColorspaceExt = hasExtension(VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME);
    std::vector<const char*> enabled = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    };
    if (hasColorspaceExt)
        enabled.push_back(VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME);

    VkApplicationInfo app{ VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.pApplicationName = "MW3 HDR10 preflight";
    app.apiVersion = VK_API_VERSION_1_0;
    VkInstanceCreateInfo info{ VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    info.pApplicationInfo = &app;
    info.enabledExtensionCount = static_cast<uint32_t>(enabled.size());
    info.ppEnabledExtensionNames = enabled.data();

    VkInstance instance = VK_NULL_HANDLE;
    VkResult result = createInstance(&info, nullptr, &instance);
    if (result != VK_SUCCESS || instance == VK_NULL_HANDLE) {
        std::fprintf(stderr, "vkCreateInstance failed (%d).\n", static_cast<int>(result));
        FreeLibrary(loader);
        return 2;
    }

    auto destroyInstance = LoadVk<PFN_vkDestroyInstance>(gip, instance, "vkDestroyInstance");
    auto createSurface = LoadVk<PFN_vkCreateWin32SurfaceKHR>(gip, instance, "vkCreateWin32SurfaceKHR");
    auto destroySurface = LoadVk<PFN_vkDestroySurfaceKHR>(gip, instance, "vkDestroySurfaceKHR");
    auto enumerateGPUs = LoadVk<PFN_vkEnumeratePhysicalDevices>(gip, instance, "vkEnumeratePhysicalDevices");
    auto getProps = LoadVk<PFN_vkGetPhysicalDeviceProperties>(gip, instance, "vkGetPhysicalDeviceProperties");
    auto getFormats = LoadVk<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
        gip, instance, "vkGetPhysicalDeviceSurfaceFormatsKHR");

    HWND window = CreateWindowExA(0, "STATIC", "MW3 HDR10 format probe",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 640, 480,
        nullptr, nullptr, GetModuleHandleA(nullptr), nullptr);
    bool hdr10Supported = false;
    if (!window || !createSurface || !destroySurface || !enumerateGPUs || !getProps || !getFormats) {
        std::fprintf(stderr, "Cannot create a Win32 surface or resolve Vulkan WSI functions.\n");
    } else {
        VkWin32SurfaceCreateInfoKHR surfaceInfo{ VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR };
        surfaceInfo.hinstance = GetModuleHandleA(nullptr);
        surfaceInfo.hwnd = window;
        VkSurfaceKHR surface = VK_NULL_HANDLE;
        result = createSurface(instance, &surfaceInfo, nullptr, &surface);
        if (result != VK_SUCCESS || surface == VK_NULL_HANDLE) {
            std::fprintf(stderr, "vkCreateWin32SurfaceKHR failed (%d).\n", static_cast<int>(result));
        } else {
            uint32_t gpuCount = 0;
            result = enumerateGPUs(instance, &gpuCount, nullptr);
            if (result == VK_SUCCESS && gpuCount) {
                std::vector<VkPhysicalDevice> gpus(gpuCount);
                result = enumerateGPUs(instance, &gpuCount, gpus.data());
                if (result == VK_SUCCESS) {
                    std::printf("VK_EXT_swapchain_colorspace available: %s\n",
                        hasColorspaceExt ? "yes" : "NO");
                    for (VkPhysicalDevice gpu : gpus) {
                        VkPhysicalDeviceProperties props{};
                        getProps(gpu, &props);
                        std::printf("GPU: %s (vendor=%04x)\n",
                            props.deviceName, props.vendorID);
                        uint32_t formatCount = 0;
                        VkResult fr = getFormats(gpu, surface, &formatCount, nullptr);
                        if (fr != VK_SUCCESS || !formatCount) {
                            std::printf("  Surface format query failed (%d)\n", static_cast<int>(fr));
                            continue;
                        }
                        std::vector<VkSurfaceFormatKHR> formats(formatCount);
                        fr = getFormats(gpu, surface, &formatCount, formats.data());
                        if (fr != VK_SUCCESS) {
                            std::printf("  Cannot enumerate actual surface formats.\n");
                            continue;
                        }
                        for (const auto& fmt : formats) {
                            if (fmt.colorSpace == VK_COLOR_SPACE_HDR10_ST2084_EXT) {
                                std::printf("  HDR10/PQ supported format: %s (VkFormat=%d)\n",
                                    Name(fmt.format), static_cast<int>(fmt.format));
                                if (fmt.format == VK_FORMAT_A2B10G10R10_UNORM_PACK32 ||
                                    fmt.format == VK_FORMAT_A2R10G10B10_UNORM_PACK32)
                                    hdr10Supported = true;
                            }
                        }
                    }
                }
            } else {
                std::fprintf(stderr, "No Vulkan physical device found.\n");
            }
            destroySurface(instance, surface, nullptr);
        }
    }

    if (window) DestroyWindow(window);
    if (destroyInstance) destroyInstance(instance, nullptr);
    FreeLibrary(loader);

    std::printf("\nHDR10 10-bit surface format reported: %s\n", hdr10Supported ? "YES" : "NO");
    std::printf("IMPORTANT: this is ONLY a Vulkan format capability check.\n");
    std::printf("It does not enable HDR, read the monitor's HDR certification,\n");
    std::printf("prove Windows HDR is switched on, or validate the modified DXVK swapchain.\n");
    return hdr10Supported ? 0 : 1;
}
