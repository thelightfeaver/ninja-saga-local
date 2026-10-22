<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Upgrade the demo account created by older builds.
     *
     * v1.0.0 seeded `macninja` as a free account with 0 tokens. The published
     * build now ships a Premium demo account so the friend receiving it can
     * test premium features (extra character slots, emblems, roulette spins,
     * pet purchases, etc.). This migration only touches the documented demo
     * account, never a real player, and preserves a password the user may have
     * changed.
     */
    public function up(): void
    {
        DB::table('users')
            ->where('username', 'macninja')
            ->where('email', 'macninja@test.local')
            ->update([
                'account_type' => 1,
                'tokens' => DB::raw('GREATEST(tokens, 1000000)'),
            ]);
    }

    public function down(): void
    {
        // The premium status is intentional; rolling back would make the
        // documented credentials worse. Nothing to undo.
    }
};
