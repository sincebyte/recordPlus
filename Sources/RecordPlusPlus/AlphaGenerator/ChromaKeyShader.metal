#include <metal_stdlib>
using namespace metal;

struct AlphaConfig {
    float4 keyColor;
    float4 borderColor;
    float thresholdLow;
    float thresholdHigh;
    float spillSuppression;
    float cornerRadius;
    float width;
    float height;
    float borderWidth;
    float contentWidth;
    float contentHeight;
    float windowX;
    float windowY;
};

inline float chromaDistance(float3 color, float3 keyColor) {
    float3 diff = color - keyColor;
    return sqrt(diff.r * diff.r * 0.3 + diff.g * diff.g * 1.0 + diff.b * diff.b * 0.3);
}

inline float3 despillColor(float3 srcColor, float3 keyColor, float alpha, float spillSuppression) {
    if (spillSuppression <= 0.0 || alpha >= 1.0) {
        return srcColor;
    }
    float spill = (1.0 - alpha) * spillSuppression;
    float3 corrected = srcColor;
    corrected.r = srcColor.r - keyColor.r * spill;
    corrected.g = srcColor.g - keyColor.g * spill;
    corrected.b = srcColor.b - keyColor.b * spill;
    return clamp(corrected, 0.0, 1.0);
}

kernel void chromaKeyKernel(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant AlphaConfig& config [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
        return;
    }

    float3 keyColor = config.keyColor.rgb;

    int2 srcPos = int2(gid) - int2(config.windowX, config.windowY);
    float4 srcColor;
    if (srcPos.x >= 0 && srcPos.x < int(config.contentWidth) &&
        srcPos.y >= 0 && srcPos.y < int(config.contentHeight)) {
        srcColor = inTexture.read(uint2(srcPos));
    } else {
        srcColor = config.keyColor;
    }

    float dist = chromaDistance(srcColor.rgb, keyColor);
    float alpha = smoothstep(config.thresholdLow, config.thresholdHigh, dist);

    if (alpha > 0.0 && alpha < 1.0) {
        float totalAlpha = alpha;
        float totalWeight = 1.0;
        int2 dirs[4] = { int2(-1, -1), int2(1, -1), int2(-1, 1), int2(1, 1) };
        for (int i = 0; i < 4; i++) {
            int2 ngid = int2(gid) + dirs[i];
            if (ngid.x >= 0 && ngid.x < int(config.width) &&
                ngid.y >= 0 && ngid.y < int(config.height)) {
                int2 nSrc = ngid - int2(config.windowX, config.windowY);
                float3 nColor;
                if (nSrc.x >= 0 && nSrc.x < int(config.contentWidth) &&
                    nSrc.y >= 0 && nSrc.y < int(config.contentHeight)) {
                    nColor = inTexture.read(uint2(nSrc)).rgb;
                } else {
                    nColor = keyColor;
                }
                float nDist = chromaDistance(nColor, keyColor);
                float nAlpha = smoothstep(config.thresholdLow, config.thresholdHigh, nDist);
                totalAlpha += nAlpha;
                totalWeight += 1.0;
            }
        }
        alpha = totalAlpha / totalWeight;
    }

    float3 finalColor = despillColor(srcColor.rgb, keyColor, alpha, config.spillSuppression);
    float finalAlpha = alpha;

    if (config.borderWidth > 0.0 && alpha > 0.5) {
        int bw = max(1, int(config.borderWidth));
        int gap = 1;

        bool skip = false;
        for (int d = 1; d <= gap + 1 && !skip; d++) {
            int2 dirs[4] = { int2(d, 0), int2(-d, 0), int2(0, d), int2(0, -d) };
            for (int i = 0; i < 4 && !skip; i++) {
                int2 ngid = int2(gid) + dirs[i];
                if (ngid.x >= 0 && ngid.x < int(config.width) &&
                    ngid.y >= 0 && ngid.y < int(config.height)) {
                    int2 nSrc = ngid - int2(config.windowX, config.windowY);
                    float nDist;
                    if (nSrc.x >= 0 && nSrc.x < int(config.contentWidth) &&
                        nSrc.y >= 0 && nSrc.y < int(config.contentHeight)) {
                        nDist = chromaDistance(inTexture.read(uint2(nSrc)).rgb, keyColor);
                    } else {
                        nDist = 0.0;
                    }
                    if (nDist < config.thresholdLow) {
                        skip = true;
                    }
                }
            }
        }

        if (!skip) {
            bool nearBg = false;
            for (int d = gap + 2; d <= gap + 1 + bw && !nearBg; d++) {
                int2 dirs[4] = { int2(d, 0), int2(-d, 0), int2(0, d), int2(0, -d) };
                for (int i = 0; i < 4 && !nearBg; i++) {
                    int2 ngid = int2(gid) + dirs[i];
                    if (ngid.x >= 0 && ngid.x < int(config.width) &&
                        ngid.y >= 0 && ngid.y < int(config.height)) {
                        int2 nSrc = ngid - int2(config.windowX, config.windowY);
                        float nDist;
                        if (nSrc.x >= 0 && nSrc.x < int(config.contentWidth) &&
                            nSrc.y >= 0 && nSrc.y < int(config.contentHeight)) {
                            nDist = chromaDistance(inTexture.read(uint2(nSrc)).rgb, keyColor);
                        } else {
                            nDist = 0.0;
                        }
                        if (nDist < config.thresholdLow) {
                            nearBg = true;
                        }
                    }
                }
            }
            if (nearBg) {
                finalAlpha = config.borderColor.a;
                finalColor = config.borderColor.rgb;
            }
        }
    }

    outTexture.write(float4(finalColor * finalAlpha, finalAlpha), gid);
}