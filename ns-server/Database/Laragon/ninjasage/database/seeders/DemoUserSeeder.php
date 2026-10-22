<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Creates the demo account documented in the README.
 *
 * It is deliberately idempotent and never touches an existing user, so
 * running the seeders again does not reset a real player's password,
 * account type or characters.
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
            'account_type' => 0,
            'email_verified_at' => now(),
        ]);
    }
}
