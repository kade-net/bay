/**
 - This module defines a fungible asset to be used for all in app purchases in the poseidon mobile app
**/

module bay::anchor {

    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    #[test_only]
    use aptos_framework::account;
    use aptos_framework::event::emit;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use kade::accounts;
    #[test_only]
    use kade::usernames;


    const SEED: vector<u8> = b"ANCHOR V1";
    const ASSET_NAME: vector<u8> = b"ANCHOR";
    const ASSET_SYMBOL: vector<u8> = b"AR";
    const ASSET_ICON: vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmSawnxuBixy8MgW8sP5sL8YDjy7rvHP9M8rPF18jfx2A4";
    const ASSET_URL: vector<u8> = b"https://kade.network";

    const EPERMISSION_DENIED: u64 = 1;
    const EUSER_NOT_REGISTERED: u64 = 2;

    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef
    }

    #[event]
    struct AnchorMintEvent has store, drop {
        user_kid: u64,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct AnchorTransferEvent has store, drop {
        user_kid: u64,
        receiver_user_kid: u64,
        amount: u64,
        timestamp: u64
    }


    fun init_module(admin: &signer) {
        let constructor_ref = &object::create_named_object(admin, ASSET_SYMBOL);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(ASSET_NAME),
            string::utf8(ASSET_SYMBOL),
            0,
            string::utf8(ASSET_ICON),
            string::utf8(ASSET_URL)
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);

        coin::register<AptosCoin>(admin);

        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset {
                mint_ref,
                burn_ref,
                transfer_ref
            }
        )

    }


    public entry fun mint(admin: &signer, user: &signer, apt_amount: u64, amount: u64) acquires ManagedFungibleAsset {
        let to = signer::address_of(user);
        assert_is_registered_user(to);
        coin::register<AptosCoin>(user);
        coin::transfer<AptosCoin>(user, @bay, apt_amount);

        let asset = get_metadata();
        let managed_fungible_asset = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
        fungible_asset::set_frozen_flag(&managed_fungible_asset.transfer_ref, to_wallet, true);

        let (user_kid, _) = accounts::get_account(to);

        emit(AnchorMintEvent {
            amount,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::transfer_with_ref(transfer_ref, from_wallet, to_wallet, amount);

        let (from_kid, _) = accounts::get_account(from);
        let (to_kid, __) = accounts::get_account(to);

        emit(AnchorTransferEvent {
            user_kid: from_kid,
            receiver_user_kid: to_kid,
            timestamp: timestamp::now_seconds(),
            amount
        })
    }

    public entry fun burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let burn_ref = &authorized_borrow_refs(admin, asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    public entry fun freeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, true);
    }

    public entry fun unfreeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, false);
    }

    public fun withdraw(admin: &signer, amount: u64, from: address): fungible_asset::FungibleAsset acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount)
    }

    public fun deposit(admin: &signer, to: address, fa: fungible_asset::FungibleAsset) acquires ManagedFungibleAsset {
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::deposit_with_ref(transfer_ref, to_wallet, fa);
    }



    // ===============
    // View Functions
    // ===============
    inline fun get_metadata(): object::Object<Metadata> {
        let asset_address = object::create_object_address(&@bay, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address,)
    }

    #[view]
    public fun get_balance(address: address): u64 {
        let metadata = get_metadata();
        let balance = primary_fungible_store::balance(address, metadata);
        balance
    }

    // ================
    // Helper Functions
    // ================
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: object::Object<Metadata>
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), EPERMISSION_DENIED);
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    inline fun assert_is_registered_user(user_address: address) {
        let (kid, _) = accounts::get_account(user_address);
        assert!(kid != 0, EUSER_NOT_REGISTERED);
    }


    // =========
    // Test only
    // =========
    #[test_only]
    public fun test_init_module(admin: &signer) {
        init_module(admin);
    }

    #[test]
    #[expected_failure(abort_code=65539)]
    public fun test_ungated_transfer_of_asset_fails() acquires  ManagedFungibleAsset {
        let admin = account::create_account_for_test(@bay);
        let aptos_framework = account::create_account_for_test(@std);
        let user = account::create_account_for_test(@0x7);
        let user2 = account::create_account_for_test(@0x8);
        let kade = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        usernames::dependancy_test_init_module(&kade);
        accounts::dependancy_test_init_module(&kade);
        init_module(&admin);

        accounts::gd_account_setup_with_self_delegate(&kade, &user, string::utf8(b"user"));
        accounts::gd_account_setup_with_self_delegate(&kade,&user2, string::utf8(b"user2"));

        mint(&admin, &user,0, 50000);

        let metadata = get_metadata();

        primary_fungible_store::transfer(&user, metadata, signer::address_of(&user2), 2000);

    }

    #[test]
    public fun test_transfer_of_asset_success() acquires  ManagedFungibleAsset {
        let admin = account::create_account_for_test(@bay);
        let aptos_framework = account::create_account_for_test(@std);
        let user = account::create_account_for_test(@0x7);
        let user2 = account::create_account_for_test(@0x8);
        let kade = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        usernames::dependancy_test_init_module(&kade);
        accounts::dependancy_test_init_module(&kade);
        init_module(&admin);

        accounts::gd_account_setup_with_self_delegate(&kade, &user, string::utf8(b"user"));
        accounts::gd_account_setup_with_self_delegate(&kade,&user2, string::utf8(b"user2"));

        mint(&admin, &user,0, 50000);

        transfer(&admin, signer::address_of(&user), signer::address_of(&user2), 20000);

        let user_1_balance = get_balance(signer::address_of(&user));
        let user_2_balance = get_balance(signer::address_of(&user2));

        assert!(user_1_balance == 30000, 3);
        assert!(user_2_balance == 20000, 4);
    }

}