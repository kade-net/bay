/**
 - This module defines a fungible asset to be used for all in app purchases in the poseidon mobile app
**/

module bay::anchor {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::simple_map;
    use aptos_std::simple_map::SimpleMap;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
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
    const EORDER_QUEUE_FULL: u64 = 3;
    const EORDER_ALREADY_IN_QUEUE: u64 = 4;
    const ENOEXISTING_ORDER: u64 = 5;

    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef
    }

    struct Order has drop, store, copy {
        initiator: address,
        apt_amount: u64,
        anchors_requested: u64,
        timestamp: u64
    }

    struct State has key {
        signer_capability: account::SignerCapability,
        orders: SimpleMap<address, Order> // max length will always be 100
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
        let (resource_signer, signer_capability) = account::create_resource_account(admin, SEED);
        let constructor_ref = &object::create_named_object(&resource_signer, ASSET_SYMBOL);

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
        );

        move_to(&resource_signer, State {
            signer_capability,
            orders: simple_map::new()
        })

    }

    public entry fun create_anchor_order(admin: &signer, apt_amount: u64, anchor_amount: u64, user_address: address) acquires State {
        assert_is_registered_user(user_address);
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let state = borrow_global_mut<State>(resource_address);

        let current_unfullfilled_orders = simple_map::length(&state.orders);

        assert!(current_unfullfilled_orders < 100, EORDER_QUEUE_FULL);

        let exists = simple_map::contains_key(&state.orders, &user_address);

        if(exists){
            simple_map::remove(&mut state.orders, &user_address);
        };

        simple_map::add(&mut state.orders,user_address, Order {
            apt_amount,
            anchors_requested: anchor_amount,
            initiator: user_address,
            timestamp: timestamp::now_microseconds()
        })

    }

    public entry fun clean_anchor_order(admin: &signer, user_address: address) acquires State {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let state = borrow_global_mut<State>(resource_address);

        simple_map::remove(&mut state.orders, &user_address);

    }

    public entry fun user_confirm_order(user: &signer) acquires State, ManagedFungibleAsset {
        let user_address = signer::address_of(user);
        assert_is_registered_user(user_address);

        let resource_address = account::create_resource_address(&@bay, SEED);
        let state = borrow_global_mut<State>(resource_address);

        let has_existing_order = simple_map::contains_key(&state.orders, &user_address);

        assert!(has_existing_order, ENOEXISTING_ORDER);

        let order = simple_map::borrow(&state.orders, &user_address);

        // register
        coin::register<AptosCoin>(user);
        // charge:
        coin::transfer<AptosCoin>(user,@bay, order.apt_amount);

        // mint
        internal_mint(user_address, order.anchors_requested);

        // clean
        simple_map::remove(&mut state.orders, &user_address);

    }




    fun internal_mint(user_address: address, amount: u64) acquires ManagedFungibleAsset {
        let to = user_address;
        assert_is_registered_user(to);
        let asset = get_metadata();
        let managed_fungible_asset = authorized_borrow_refs(asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
        fungible_asset::set_frozen_flag(&managed_fungible_asset.transfer_ref, to_wallet, true);

        let (user_kid, _) = accounts::get_account(to);

        event::emit(AnchorMintEvent {
            amount,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::transfer_with_ref(transfer_ref, from_wallet, to_wallet, amount);

        let (from_kid, _) = accounts::get_account(from);
        let (to_kid, __) = accounts::get_account(to);

        event::emit(AnchorTransferEvent {
            user_kid: from_kid,
            receiver_user_kid: to_kid,
            timestamp: timestamp::now_seconds(),
            amount
        })
    }

    public entry fun admin_burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let burn_ref = &authorized_borrow_refs(asset).burn_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::burn_from(burn_ref, from_wallet, amount);
    }

    public entry fun admin_freeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, true);
    }

    public entry fun admin_unfreeze_account(admin: &signer, account: address) acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(asset).transfer_ref;
        let wallet = primary_fungible_store::ensure_primary_store_exists(account, asset);
        fungible_asset::set_frozen_flag(transfer_ref, wallet, false);
    }

    public fun admin_withdraw(admin: &signer, amount: u64, from: address): fungible_asset::FungibleAsset acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from, asset);
        fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount)
    }

    public fun admin_deposit(admin: &signer, to: address, fa: fungible_asset::FungibleAsset) acquires ManagedFungibleAsset {
        assert!(signer::address_of(admin) == @bay, EPERMISSION_DENIED);
        let asset = get_metadata();
        let transfer_ref = &authorized_borrow_refs(asset).transfer_ref;
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::deposit_with_ref(transfer_ref, to_wallet, fa);
    }



    // ===============
    // View Functions
    // ===============
    inline fun get_metadata(): object::Object<Metadata> {
        let resource_address = account::create_resource_address(&@bay, SEED);
        let asset_address = object::create_object_address(&resource_address, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address,)
    }

    #[view]
    public fun get_balance(address: address): u64 {
        let metadata = get_metadata();
        let balance = primary_fungible_store::balance(address, metadata);
        balance
    }

    #[view]
    public fun get_current_order(address: address): vector<Order> acquires  State {
        let state = borrow_global<State>(address);
        let has_existing_order = simple_map::contains_key(&state.orders, &address);
        if(!has_existing_order){
            return vector::empty()
        };
        let order = simple_map::borrow(&state.orders, &address);
        let orders_vector = vector::empty<Order>();
        vector::push_back(&mut orders_vector, *order);

        return orders_vector

    }

    // ================
    // Helper Functions
    // ================
    inline fun authorized_borrow_refs(
        asset: object::Object<Metadata>
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        let resource_address = account::create_resource_address(&@bay,SEED);
        assert!(object::is_owner(asset, resource_address), EPERMISSION_DENIED);
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

    #[test_only]
    public entry fun mint(admin: &signer, user: &signer, apt_amount: u64, anchor_amount: u64) acquires State, ManagedFungibleAsset {
        create_anchor_order(admin ,apt_amount, anchor_amount, signer::address_of(user));
        user_confirm_order(user);
    }

    #[test]
    #[expected_failure(abort_code=65539)]
    public fun test_ungated_transfer_of_asset_fails() acquires  ManagedFungibleAsset, State {
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
    public fun test_transfer_of_asset_success() acquires  ManagedFungibleAsset, State {
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