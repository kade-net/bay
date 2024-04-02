module bay::pearls {

    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::object;
    use aptos_framework::object::TransferRef;
    use aptos_token_objects::collection;
    use aptos_token_objects::collection::MutatorRef;
    use aptos_token_objects::token;
    use aptos_token_objects::token::BurnRef;
    use bay::anchor;
    use kade::accounts;
    #[test_only]
    use aptos_framework::timestamp;
    #[test_only]
    use kade::usernames;

    const SEED: vector<u8> = b"bay::pearls";
    const EOPERATION_NOT_PERMITTED: u64 = 1;
    const ECOLLECTION_DOES_NOT_EXIST: u64 = 2;


    struct State has key {
        signer_capability: account::SignerCapability,
    }


    struct CollectionMeta has store, drop, key {
        is_gated: bool,
        anchor_amount: u64,
        is_soul_bound: bool,
        mut_ref: MutatorRef,
        uri: string::String,
        description: string::String
    }

    struct NonBoundToken has store, drop, key {
        transfer_ref: TransferRef,
        burn_ref: BurnRef
    }

    fun init_module(admin: &signer) {
        let (resource_signer, signer_cap) = account::create_resource_account(admin, SEED);

        move_to<State>(&resource_signer, State {
            signer_capability: signer_cap
        })
    }

    public entry fun create_collection(
        admin: &signer,
        is_gated:bool,
        anchor_amount: u64,
        is_soul_bound: bool,
        name: string::String,
        description:string::String,
        uri: string::String,
        max_supply: u64,
    ) acquires State {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let state = borrow_global<State>(resource_address);
        let resource_signer = account::create_signer_with_capability(&state.signer_capability);

        if(max_supply == 0){
            let constructor_ref = collection::create_unlimited_collection(
                &resource_signer,
                description,
                name,
                option::none(),
                uri
            );

            let meta = CollectionMeta {
                anchor_amount,
                is_gated,
                is_soul_bound,
                mut_ref: collection::generate_mutator_ref(&constructor_ref),
                uri,
                description
            };

            let object_signer = object::generate_signer(&constructor_ref);


            move_to(&object_signer, meta);

        }
        else {
            let constructor_ref = collection::create_fixed_collection(
                &resource_signer,
                description,
                max_supply,
                name,
                option::none(),
                uri
            );

            let meta = CollectionMeta {
                anchor_amount,
                is_gated,
                is_soul_bound,
                mut_ref: collection::generate_mutator_ref(&constructor_ref),
                uri,
                description
            };

            let object_signer = object::generate_signer(&constructor_ref);


            move_to(&object_signer, meta);

        }


    }

    fun mint_from_collection(
        user_address: address,
        collection_name: string::String,
        variant_uri: string::String
    ) acquires CollectionMeta, State {
        let username = accounts::get_current_username(user_address);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let state = borrow_global<State>(resource_address);
        let resource_signer = account::create_signer_with_capability(&state.signer_capability);
        let collection_meta_address = object::create_object_address(&resource_address, *string::bytes(&collection_name));
        assert!(object::is_object(collection_meta_address), ECOLLECTION_DOES_NOT_EXIST);

        let meta = borrow_global<CollectionMeta>(collection_meta_address);

        let mint_uri = meta.uri;

        if(string::length(&variant_uri) != 0){
            mint_uri = variant_uri
        };


            let token_constructor_ref = token::create(
                &resource_signer,
                collection_name,
                meta.description,
                username,
                option::none(),
                mint_uri
            );

            let token_signer = object::generate_signer(&token_constructor_ref);
            let burn_ref = token::generate_burn_ref(&token_constructor_ref);
            let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
            let linear_ref = object::generate_linear_transfer_ref(&transfer_ref);
            object::transfer_with_ref(linear_ref, user_address);

            if(meta.is_gated || meta.is_soul_bound){
                object::disable_ungated_transfer(&transfer_ref);
            };

            move_to(&token_signer, NonBoundToken {
                burn_ref,
                transfer_ref
            });

    }


    public entry fun admin_mint_for_user(admin: &signer, user_address: address, collection_name: string::String, variant_uri: string::String) acquires CollectionMeta, State {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        mint_from_collection(user_address,collection_name, variant_uri);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let collection_meta_address = object::create_object_address(&resource_address, *string::bytes(&collection_name));
        assert!(object::is_object(collection_meta_address), ECOLLECTION_DOES_NOT_EXIST);

        let meta = borrow_global<CollectionMeta>(collection_meta_address);

        if(meta.anchor_amount > 0){
            anchor::transfer(admin, user_address, @bay, meta.anchor_amount);
        }
    }



    // tests
    #[test]
    fun test_create_fixed_collection() acquires State{
        let admin = account::create_account_for_test(@bay);

        init_module(&admin);

        create_collection(
            &admin,
            true,
            0,
            true,
            string::utf8(b"ere"),
            string::utf8(b"qqqqqqqqqqqqqqqqqjjd"),
            string::utf8(b"fff"),
            1000
        );
    }

    #[test]
    fun test_create_unlimited_collection() acquires State{
        let admin = account::create_account_for_test(@bay);

        init_module(&admin);

        create_collection(
            &admin,
            true,
            0,
            true,
            string::utf8(b"ere"),
            string::utf8(b"qqqqqqqqqqqqqqqqqjjd"),
            string::utf8(b"fff"),
            0
        );
    }

    #[test]
    fun test_mint_from_limited_collection() acquires State, CollectionMeta {
        let admin = account::create_account_for_test(@bay);
        let kade_admin = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x10);
        let aptos_framework = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(&admin);

        create_collection(
            &admin,
            true,
            0,
            true,
            string::utf8(b"coll"),
            string::utf8(b"coll"),
            string::utf8(b"coll"),
            1000
        );

        usernames::dependancy_test_init_module(&kade_admin);
        accounts::dependancy_test_init_module(&kade_admin);

        accounts::account_setup_with_self_delegate(&user,string::utf8(b"chen"));


        admin_mint_for_user(
            &admin,
            signer::address_of(&user),
            string::utf8(b"coll"),
            string::utf8(b"")
        );
    }




}
