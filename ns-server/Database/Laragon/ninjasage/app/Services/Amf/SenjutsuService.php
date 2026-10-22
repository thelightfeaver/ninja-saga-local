<?php

namespace App\Services\Amf;

use App\Services\Amf\SenjutsuService\QueryService;
use App\Services\Amf\SenjutsuService\UpgradeService;
use App\Services\Amf\SenjutsuService\EquipService;
use App\Services\Amf\SenjutsuService\DiscoverService;
use App\Services\Amf\SenjutsuService\PackageService;

class SenjutsuService
{
    private QueryService $queryService;
    private UpgradeService $upgradeService;
    private EquipService $equipService;
    private DiscoverService $discoverService;
    private PackageService $packageService;

    public function __construct()
    {
        $this->queryService = new QueryService();
        $this->upgradeService = new UpgradeService();
        $this->equipService = new EquipService();
        $this->discoverService = new DiscoverService();
        $this->packageService = new PackageService();
    }

    /**
     * getSenjutsuSkills
     * Params: [charId, sessionKey]
     */
    public function getSenjutsuSkills($charId, $sessionKey)
    {
        return $this->queryService->getSenjutsuSkills($charId, $sessionKey);
    }

    /**
     * upgradeSkill
     * Params: [charId, sessionKey, baseSkillId, isMax]
     */
    public function upgradeSkill($charId, $sessionKey, $baseSkillId, $isMax = false)
    {
        return $this->upgradeService->upgradeSkill($charId, $sessionKey, $baseSkillId, $isMax);
    }

    /**
     * equipSkill
     * Params: [charId, sessionKey, skills]
     */
    public function equipSkill($charId, $sessionKey, $skills)
    {
        return $this->equipService->equipSkill($charId, $sessionKey, $skills);
    }

    /**
     * discoverSenjutsu
     * Params: [charId, sessionKey, type]
     */
    public function discoverSenjutsu($charId, $sessionKey, $type)
    {
        return $this->discoverService->discoverSenjutsu($charId, $sessionKey, $type);
    }

    /**
     * buyPackageSS
     * Params: [charId, sessionKey, packageIndex]
     *
     * Called by the "Boost SS" button in the Senjutsu profile.
     */
    public function buyPackageSS($charId, $sessionKey, $packageIndex)
    {
        return $this->packageService->buyPackageSS($charId, $sessionKey, $packageIndex);
    }
}
