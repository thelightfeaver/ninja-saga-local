<?php

namespace App\Services\Amf\SenjutsuService;

use App\Models\Character;
use App\Models\User;
use App\Services\Amf\Concerns\ValidatesSession;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class PackageService
{
    use ValidatesSession;

    /**
     * Mirrors the four packages in the client's SenjutsuProfile.sageScrollShop.
     * [price in tokens, SS granted]
     *
     * Boosted x10: the client still paints the original amounts (10/55/120/250)
     * but the server grants 10x SS.  The actual total is returned in `ss` and
     * the client overwrites Character.character_ss with it.
     */
    private const PACKAGES = [
        0 => ['price' => 20,  'amount' => 100],   // 10x of 10
        1 => ['price' => 100, 'amount' => 550],   // 10x of 55
        2 => ['price' => 200, 'amount' => 1200],  // 10x of 120
        3 => ['price' => 400, 'amount' => 2500],  // 10x of 250
    ];

    /**
     * buyPackageSS
     * Params: [charId, sessionKey, packageIndex]
     *
     * The client's "Boost SS" shop calls SenjutsuService.buyPackageSS.
     * It deducts the token price locally, so the server must deduct the
     * same amount and return the new SS total in `ss`.
     */
    public function buyPackageSS($charId, $sessionKey, $packageIndex)
    {
        $guard = $this->guardCharacterSession((int) $charId, $sessionKey);
        if ($guard) {
            return $guard;
        }

        $index = (int) $packageIndex;
        if (!isset(self::PACKAGES[$index])) {
            return ['status' => 2, 'result' => 'Invalid Sage Scroll package.'];
        }

        $package = self::PACKAGES[$index];
        Log::info("AMF Senjutsu.buyPackageSS: Char $charId Package $index ({$package['amount']} SS / {$package['price']} tokens)");

        try {
            return DB::transaction(function () use ($charId, $package) {
                $char = Character::lockForUpdate()->find($charId);
                if (!$char) {
                    return ['status' => 0, 'error' => 'Character not found'];
                }

                $user = User::lockForUpdate()->find($char->user_id);
                if (!$user) {
                    return ['status' => 0, 'error' => 'User not found'];
                }

                if ($user->tokens < $package['price']) {
                    return ['status' => 2, 'result' => 'Not enough tokens!'];
                }

                $user->tokens -= $package['price'];
                $user->save();

                $char->ss += $package['amount'];
                $char->save();

                return [
                    'status' => 1,
                    'error' => 0,
                    'ss' => (int) $char->ss,
                    'account_tokens' => (int) $user->tokens,
                    'result' => 'Purchased ' . $package['amount'] . ' Sage Scrolls!',
                ];
            });
        } catch (\Throwable $e) {
            Log::error('Buy Sage Scroll package error: ' . $e->getMessage());
            return ['status' => 0, 'error' => 'Internal Server Error'];
        }
    }
}
