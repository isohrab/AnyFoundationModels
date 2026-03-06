#if MLX_ENABLED
import Foundation
@preconcurrency import MLXLMCommon

struct MLXPrefixCacheEntry {
    let cacheKey: MLXPrefixCacheKey
    let kvCache: [KVCache]
    let prefixTokenCount: Int
    let createdAt: Date
    let runtimeFamily: MLXRuntimeFamily
    let modality: MLXModalityFamily
}

struct MLXCacheReuseDecision {
    let cache: [KVCache]?
    let prefixTokenCount: Int?
    let outcome: String
}

struct MLXPrefixCacheStore {
    var entry: MLXPrefixCacheEntry?

    mutating func lookup(
        plan: MLXExecutionPlan,
        metadata: MLXModelMetadata
    ) -> MLXCacheReuseDecision {
        guard plan.cachePlan.reuseScope == .prefixReusable,
              let cacheKey = plan.cachePlan.cacheKey
        else {
            return MLXCacheReuseDecision(cache: nil, prefixTokenCount: nil, outcome: MLXCacheInvalidationReason.noReusablePrefix.rawValue)
        }

        guard let entry else {
            return MLXCacheReuseDecision(cache: nil, prefixTokenCount: nil, outcome: MLXCacheInvalidationReason.noStoredCache.rawValue)
        }

        guard entry.cacheKey == cacheKey,
              entry.runtimeFamily == metadata.runtimeFamily,
              entry.modality == metadata.modalityFamily
        else {
            return MLXCacheReuseDecision(cache: nil, prefixTokenCount: nil, outcome: MLXCacheInvalidationReason.cacheKeyChanged.rawValue)
        }

        return MLXCacheReuseDecision(
            cache: entry.kvCache,
            prefixTokenCount: entry.prefixTokenCount,
            outcome: "hit"
        )
    }

    mutating func store(
        cacheKey: MLXPrefixCacheKey,
        kvCache: [KVCache],
        prefixTokenCount: Int,
        metadata: MLXModelMetadata
    ) {
        entry = MLXPrefixCacheEntry(
            cacheKey: cacheKey,
            kvCache: kvCache,
            prefixTokenCount: prefixTokenCount,
            createdAt: Date(),
            runtimeFamily: metadata.runtimeFamily,
            modality: metadata.modalityFamily
        )
    }
}
#endif
