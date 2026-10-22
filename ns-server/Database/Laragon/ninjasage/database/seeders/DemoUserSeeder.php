<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Creates the demo account documented in the README.
 *
 * The account is Premium (account_type = 1) and starts with 1,000,000 tokens,
 * so the friend receiving the build can try every premium feature and shop
 * item without grinding. It is deliberately idempotent and never touches an
 * existing user's password, so running the seeders again does not reset a real
 * player's credentials or characters.
 */
class DemoUserSeeder extends Seeder
{
    public function run(): void
    {
        if (User::where('username', 'macninja')->exists()) {
            return;
        }

        User::create([
            'name' => 'MacNinja',
            'username' => 'macninja',
            'email' => 'macninja@test.local',
            'password' => 'ninja1234',
            'account_type' => 1,
            'tokens' => 1000000,
            'email_verified_at' => now(),
        ]);
    }
}
