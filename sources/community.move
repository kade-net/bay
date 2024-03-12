/**
Bay, is an extension of kade, and relies on the kade network smart contract for user identity
commnunities are one of the extensions that bay brings to kade's decentralized social graph.
communities are namespaces under which users can discuss related content and topics
users can create communities
users can join communities
members of communities can post to the community
**/


module bay::community {

    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::emit;
    use aptos_framework::object;
    use aptos_framework::object::{ExtendRef, DeriveRef, TransferRef};
    use aptos_framework::timestamp;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use bay::anchor;
    use kade::usernames;
    use kade::accounts;
    #[test_only]
    use aptos_framework::event::emitted_events;

    const SEED: vector<u8> = b"BAY COMMUNITIES V_0_0_1";

    const COMMUNITY_CREATION_ANCHOR_AMOUNT: u64 = 2500;

    const COLLECTION_NAME: vector<u8> = b"KADE COMMUNITIES V_0_0_1";
    const COLLECTION_DESCRIPTION: vector<u8> = b"A collection of all communities on kade.";
    const COLLECTION_URI: vector<u8> = b"https://kade.network";


    const ECOMMUNITY_NAME_TAKEN: u64 = 11;
    const EUSER_NOT_REGISTERED: u64 = 12;
    const ECOMMUNITY_DOES_NOT_EXIST: u64 = 13;
    const EMEMBERSHIP_ALREADY_EXISTS: u64 = 14;
    const EDOES_NOT_OWN_USERNAME: u64 = 15;
    const EDELEGATE_NOT_REGISTERED: u64 = 16;
    const EMEMBERSHIP_DOES_NOT_EXIST: u64 = 17;
    const EUSER_DOES_NOT_OWN_MEMBERSHIP: u64 = 18;
    const ECOMMUNITY_CREATOR_CANNOT_DELETE_MEMBERSHIP: u64 = 19;
    const EWRONG_MEMBER: u64 = 20;
    const EUNKNOWN_MEMBERSHIP_ERROR: u64 = 21;
    const EMEMBERSHIP_NOT_INACTIVE: u64 = 22;
    const EADDRESS_NOT_OWNER: u64 = 23;
    const ECANNOT_MAKE_MEMBER_OWNER: u64 = 24;
    const EOPERATION_NOT_PERMITTED: u64 = 25;


    struct CommunityRegistry has key, store {
        registered_communities: u64,
        signer_capability: account::SignerCapability,
        transfer_ref: TransferRef,
        extend_ref: ExtendRef,
        derive_ref: DeriveRef
    }

    struct Community has key, store {
        name: string::String,
        description: string::String,
        rules: string::String,
        creator: address,
        hosts: vector<address>,
        created: u64,
        bid: u64,
        total_memberships: u64,
        transfer_ref: TransferRef,
        membership_transfer_ref: TransferRef
    }

    #[event]
    struct  CommunityRegisteredEvent has store, drop {
        name: string::String,
        description: string::String,
        rules: string::String,
        creator: address,
        bid: u64,
        user_kid: u64,
        timestamp: u64,
    }

    struct Membership has key, store {
        owner: address,
        community_name: string::String,
        community_address: address,
        community_id: u64,
        joined: u64,
        membership_number: u64,
        transfer_ref: TransferRef,
        type: u64 // 0 - owner, 1 - host, 2 - normal user
    }

    #[event]
    struct MemberJoinEvent has store, drop {
        owner: address,
        community_name: string::String,
        timestamp: u64,
        bid: u64,
        type: u64,
        user_kid: u64,
    }

    #[event]
    struct MembershipChangeEvent has store, drop {
        type: u64,
        made_by: address,
        membership_owner: address,
        community_name: string::String,
        community_id: u64,
        membership_id: u64,
        timestamp: u64,
        user_kid: u64,
    }

    #[event]
    struct MembershipDeleteEvent has store, drop {
        community_name: string::String,
        community_id: u64,
        membership_id: u64,
        user_kid: u64,
        timestamp: u64,
    }

    #[event]
    struct MembershipReclaimEvent has store, drop {
        community_id: u64,
        membership_id: u64,
        user_kid: u64,
        timestamp: u64,
    }

    fun init_module(admin: &signer){
        let (resource_account_signer, signer_capability) = account::create_resource_account(admin, SEED);

        let constructor_ref = collection::create_unlimited_collection(
            &resource_account_signer,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let derive_ref = object::generate_derive_ref(&constructor_ref);
        move_to(&resource_account_signer, CommunityRegistry {
            signer_capability,
            registered_communities: 100, // First 100 error codes are reserved for error messages
            extend_ref,
            transfer_ref,
            derive_ref
        })
    }

    fun create_community(user_address: address, community_name: string::String, community_description: string::String, community_rules: string::String) acquires CommunityRegistry {
        assert_name_available(&community_name);
        let resource_address = account::create_resource_address(&@bay,SEED);
        let registry = borrow_global_mut<CommunityRegistry>(resource_address);
        let resource_signer = account::create_signer_with_capability(&registry.signer_capability);
        let (account_kid, _) = accounts::get_account(user_address);
        assert!(account_kid != 0, EUSER_NOT_REGISTERED);

        let community_constructor_ref = collection::create_unlimited_collection(
            &resource_signer,
            community_description,
            community_name,
            option::none(),
            string::utf8(COLLECTION_URI)
        );


        let constructor_ref = token::create_named_token(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            community_description,
            community_name,
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        let token_signer = object::generate_signer(&constructor_ref);

        let bid = registry.registered_communities;
        let community = Community {
            transfer_ref: object::generate_transfer_ref(&constructor_ref),
            name: community_name,
            description: community_description,
            bid,
            created: timestamp::now_seconds(),
            creator: user_address,
            hosts: vector::empty(),
            rules: community_rules,
            total_memberships: 0,
            membership_transfer_ref: object::generate_transfer_ref(&community_constructor_ref)
        };

        move_to(&token_signer, community);

        let record_object = object::object_from_constructor_ref<Community>(&constructor_ref);

        object::transfer(&resource_signer, record_object, user_address);

        registry.registered_communities = registry.registered_communities + 1;

        let (user_kid, _) = accounts::get_account(user_address);

        emit(CommunityRegisteredEvent {
            creator: user_address,
            timestamp: timestamp::now_seconds(),
            rules: community_rules,
            description: community_description,
            bid,
            name: community_name,
            user_kid
        })

    }

    public entry fun admin_create_community(admin: &signer, user_address: address, username: string::String, community_name: string::String, community_description: string::String, community_rules: string::String ) acquires CommunityRegistry, Community {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        let owns_username = usernames::is_address_username_owner(user_address, username);
        assert!(owns_username, EDOES_NOT_OWN_USERNAME);
        create_community(user_address, community_name, community_description, community_rules);
        create_membership(user_address, username, community_name, 0);
        // PAY FOR COMMUNITY CREATION
        anchor::transfer(admin, user_address, @bay, COMMUNITY_CREATION_ANCHOR_AMOUNT);
    }

    fun create_membership(user_address: address, username: string::String, community_name: string::String, type: u64) acquires CommunityRegistry, Community {
        // Validation for ownership of the username can occur at the caller's level
        assert_community_exists(&community_name);
        let (account_kid, _) = accounts::get_account(user_address);
        assert!(account_kid != 0, EUSER_NOT_REGISTERED);
        assert_membership_does_not_exist(&community_name, &username);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let registry = borrow_global<CommunityRegistry>(resource_address);
        let resource_signer = account::create_signer_with_capability(&registry.signer_capability);

        let community_address = get_community_address(&community_name);
        let community = borrow_global_mut<Community>(community_address);



        let constructor_ref  = token::create_named_token(
            &resource_signer,
            community_name,
            username,
            username,
            option::none(),
            string::utf8(COLLECTION_URI),
        );

        let token_signer = object::generate_signer(&constructor_ref);

        let membership = Membership {
            community_name,
            owner: user_address,
            community_address,
            joined: timestamp::now_seconds(),
            membership_number: community.total_memberships,
            transfer_ref: object::generate_transfer_ref(&constructor_ref),
            type,
            community_id: community.bid
        };
        let bid = membership.membership_number;


        move_to(&token_signer, membership);

        let record_object = object::object_from_constructor_ref<Membership>(&constructor_ref);

        object::transfer(&resource_signer, record_object, user_address);

        community.total_memberships = community.total_memberships + 1;

        let (user_kid, _) = accounts::get_account(user_address);

        emit(MemberJoinEvent {
            user_kid,
            community_name,
            bid,
            timestamp: timestamp::now_seconds(),
            owner: user_address,
            type
        })

    }

    public entry fun admin_create_membership(admin: &signer, user_address: address, username: string::String, community_name: string::String) acquires  CommunityRegistry, Community, Membership {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        assert_user_exists(&user_address);
        let owns_username = usernames::is_address_username_owner(user_address, username);
        assert!(owns_username, EDOES_NOT_OWN_USERNAME);
        let is_membership_reclaimable = is_membership_inactive(user_address, username, community_name);
        if(is_membership_reclaimable){
            reclaim_membership(user_address, username, community_name);
        }else{
            create_membership(user_address, username, community_name, 2);
        }
    }

    fun delete_membership(user_address: address, username: string::String, community: string::String) acquires  Membership, Community {
        // simply transfer membership to the resource address since named objects are not deletable
        let resource_address = account::create_resource_address(&@bay, SEED);
        assert_community_exists(&community);

        let community_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &community);
        let communityObject = borrow_global<Community>(community_address);
        assert!(communityObject.creator != user_address, ECOMMUNITY_CREATOR_CANNOT_DELETE_MEMBERSHIP);

        let token_address = token::create_token_address(&resource_address, &community, &username);
        let is_object = object::is_object(token_address);

        assert!(is_object, EMEMBERSHIP_DOES_NOT_EXIST);
        assert!(exists<Membership>(token_address), EMEMBERSHIP_DOES_NOT_EXIST);

        let membership = borrow_global<Membership>(token_address);
        assert!(membership.owner == user_address, EWRONG_MEMBER);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&membership.transfer_ref);


        // Membership object gets reclaimed by the resource account
        object::transfer_with_ref(linear_transfer_ref, resource_address);

        let (user_kid, _) = accounts::get_account(user_address);

        emit(MembershipDeleteEvent {
            timestamp: timestamp::now_seconds(),
            community_name: community,
            user_kid,
            community_id: communityObject.bid,
            membership_id: membership.membership_number
        });


    }

    public entry fun admin_delete_membership(admin: &signer, user_address: address, username: string::String, community: string::String) acquires Membership, Community {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        assert_user_exists(&user_address);
        assert_user_owns_membership(user_address, &username, &community);
        delete_membership(user_address, username, community);
    }

    fun reclaim_membership(user_address: address, username: string::String, community: string::String) acquires  Membership {
        assert_membership_reclaimable(&user_address, &username, &community);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let token_address = token::create_token_address(&resource_address, &community, &username);

        let membership = borrow_global<Membership>(token_address);

        let linear_ref = object::generate_linear_transfer_ref(&membership.transfer_ref);

        object::transfer_with_ref(linear_ref, user_address); // Back from resource address to the original user

        let (user_kid, _) = accounts::get_account(user_address);

        emit(MembershipReclaimEvent {
            membership_id: membership.membership_number,
            community_id: membership.community_id,
            user_kid,
            timestamp: timestamp::now_seconds()
        })
    }

    fun change_membership_type(host_address: address, host_username: string::String, member_address: address, member_username: string::String, community: string::String, type: u64) acquires Community, Membership {
        assert!(type != 0, ECANNOT_MAKE_MEMBER_OWNER);
        let resource_address = account::create_resource_address(&@bay, SEED);
        let community_token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &community);
        assert!(exists<Community>(community_token_address), ECOMMUNITY_DOES_NOT_EXIST);
        let host_token_address = token::create_token_address(&resource_address, &community, &host_username);
        let member_token_address = token::create_token_address(&resource_address, &community, &member_username);

        assert!(exists<Membership>(host_token_address), EMEMBERSHIP_DOES_NOT_EXIST);
        let host_object = object::address_to_object<Membership>(host_token_address);
        assert!(object::owns(host_object, host_address), EADDRESS_NOT_OWNER);
        assert!(exists<Membership>(member_token_address), EMEMBERSHIP_DOES_NOT_EXIST);
        let member_object = object::address_to_object<Membership>(member_token_address);
        assert!(object::owns(member_object, member_address), EADDRESS_NOT_OWNER);

        let community_registry = borrow_global<Community>(community_token_address);
        assert!(community_registry.creator == host_address, EADDRESS_NOT_OWNER);

        let new_host_membership = borrow_global_mut<Membership>(member_token_address);
        new_host_membership.type = 1; // 1 for host

        let (user_kid, _) = accounts::get_account(member_address);

        emit(MembershipChangeEvent {
            timestamp: timestamp::now_seconds(),
            user_kid,
            community_id: new_host_membership.community_id,
            membership_id: new_host_membership.membership_number,
            community_name: new_host_membership.community_name,
            type: new_host_membership.type,
            made_by: host_address,
            membership_owner: new_host_membership.owner
        })
    }


    public entry fun admin_change_membership(admin: &signer, user_address: address, host_username: string::String, member_address: address, member_username: string::String, community: string::String, type: u64) acquires  Community, Membership {
        assert!(signer::address_of(admin) == @bay, EOPERATION_NOT_PERMITTED);
        assert_user_exists(&user_address);
        assert_user_exists(&member_address);
        assert_user_owns_membership(user_address, &host_username, &community);
        assert_user_owns_membership(member_address, &member_username, &community);
        change_membership_type(user_address, host_username, member_address, member_username, community, type);
    }







    // ================
    // Inline functions
    // ================


    inline fun assert_name_available(community_name: &string::String) {
        let resource_address = account::create_resource_address(&@bay,SEED);

        let token_address = token::create_token_address(&resource_address,&string::utf8(COLLECTION_NAME), community_name);
        let is_object = object::is_object(token_address);


        assert!(!is_object, ECOMMUNITY_NAME_TAKEN);
        assert!(!exists<Community>(token_address), ECOMMUNITY_NAME_TAKEN);
    }

    inline fun assert_community_exists(community_name: &string::String) {
        let resource_address = account::create_resource_address(&@bay,SEED);

        let token_address = token::create_token_address(&resource_address,&string::utf8(COLLECTION_NAME), community_name);
        let is_object = object::is_object(token_address);


        assert!(is_object, ECOMMUNITY_DOES_NOT_EXIST);
        assert!(exists<Community>(token_address), ECOMMUNITY_DOES_NOT_EXIST);
    }

    inline fun assert_membership_does_not_exist(community_name: &string::String, username: &string::String) {
        let resource_address = account::create_resource_address(&@bay,SEED);

        let token_address = token::create_token_address(&resource_address,community_name, username);
        let is_object = object::is_object(token_address);

        assert!(!is_object, EMEMBERSHIP_ALREADY_EXISTS);
        assert!(!exists<Membership>(token_address), EMEMBERSHIP_ALREADY_EXISTS);

    }

    inline fun get_community_address(community_name: &string::String):address {
        let resource_address = account::create_resource_address(&@bay,SEED);

        let token_address = token::create_token_address(&resource_address,&string::utf8(COLLECTION_NAME), community_name);
        let is_object = object::is_object(token_address);

        assert!(is_object, ECOMMUNITY_DOES_NOT_EXIST);
        assert!(exists<Community>(token_address), ECOMMUNITY_DOES_NOT_EXIST);

        token_address
    }

    inline fun assert_user_owns_membership(user_address: address, username: &string::String, community_name: &string::String) {
        let resource_address = account::create_resource_address(&@bay,SEED);

        let token_address = token::create_token_address(&resource_address,community_name, username);
        let is_object = object::is_object(token_address);

        assert!(is_object, EMEMBERSHIP_DOES_NOT_EXIST);
        assert!(exists<Membership>(token_address), EMEMBERSHIP_DOES_NOT_EXIST);
        let membership_object = object::address_to_object<Membership>(token_address);

        assert!(object::owns(membership_object, user_address),EUSER_DOES_NOT_OWN_MEMBERSHIP );
    }

    inline fun assert_membership_reclaimable(user_address: &address, username: &string::String, community: &string::String) acquires Membership {
        let resource_address = account::create_resource_address(&@bay, SEED);

        let token_address = token::create_token_address(&resource_address, community, username);
        let is_object = object::is_object(token_address);

        assert!(is_object, EMEMBERSHIP_DOES_NOT_EXIST);
        let membership_object = object::address_to_object<Membership>(token_address);
        assert!(object::owns(membership_object, resource_address), EMEMBERSHIP_NOT_INACTIVE);

        let membership = borrow_global<Membership>(token_address);

        assert!(membership.owner == *user_address, EWRONG_MEMBER);
    }

    inline fun assert_user_exists(user_address: &address) {
        let (kid, _) = accounts::get_account(*user_address);
        assert!(kid != 0, EUSER_NOT_REGISTERED);
    }

    #[view]
    fun is_membership_inactive(user_address: address, username: string::String, community: string::String): bool acquires Membership {
        let resource_address = account::create_resource_address(&@bay, SEED);

        let token_address = token::create_token_address(&resource_address, &community, &username);
        let is_object = object::is_object(token_address);

        if(!is_object){
            return false
        };
        let membership_object = object::address_to_object<Membership>(token_address);
        if(object::owns(membership_object, resource_address)){

            let membership = borrow_global<Membership>(token_address);

            if(membership.owner == user_address){
                return true
            };
            return false
        };

        false
    }

    #[view]
    fun get_account_address_from_delegate(delegate: address): address {
        let (kid, account_address) = accounts::delegate_get_owner(delegate);
        assert!(kid != 0, EUSER_NOT_REGISTERED);
        account_address
    }

    // ==========
    // Tests
    // ==========

    #[test]
    fun test_init_module() {
        let admin_signer = account::create_account_for_test(@bay);
        let aptos_account =account::create_account_for_test(@0x1);
        let kade_account = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_account);
        //let kade_network = account::create_account_for_test(@kade);
        usernames::dependancy_test_init_module(&kade_account);
        accounts::dependancy_test_init_module(&kade_account);
        init_module(&admin_signer);

        let expected_resource_address = account::create_resource_address(&@bay, SEED);
        assert!(exists<CommunityRegistry>(expected_resource_address), 1);

    }

    #[test]
    fun test_create_community_as_user() acquires CommunityRegistry, Community {
        let lUSERNAME = string::utf8(b"bay");
        let lCOMMUNITY_NAME = string::utf8(b"the bay");
        let lCOMMUNITY_DESCRIPTION = string::utf8(b"coolest");
        let lCOMMUNITY_RULES = string::utf8(b"some rules");
        let resource_address = account::create_resource_address(&@bay, SEED);

        let admin_signer = account::create_account_for_test(@bay);
        let user = account::create_account_for_test(@0x4);
        let aptos_account =account::create_account_for_test(@0x1);
        let kade_account = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_account);

        usernames::dependancy_test_init_module(&kade_account);
        accounts::dependancy_test_init_module(&kade_account);
        init_module(&admin_signer);
        anchor::test_init_module(&admin_signer);


        usernames::claim_username(&user, string::utf8(b"bay"));
        accounts::create_account(&user, string::utf8(b"bay"));

        anchor::mint(&admin_signer, signer::address_of(&user), COMMUNITY_CREATION_ANCHOR_AMOUNT);
        admin_create_community(&admin_signer, signer::address_of(&user), lUSERNAME, lCOMMUNITY_NAME, lCOMMUNITY_DESCRIPTION, lCOMMUNITY_RULES);

        let expected_community_token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &lCOMMUNITY_NAME);
        assert!(exists<Community>(expected_community_token_address), 2);

        let community_create_events = emitted_events<CommunityRegisteredEvent>();
        let membership_create_events = emitted_events<MemberJoinEvent>();
        assert!(vector::length(&community_create_events) == 1, 0);
        assert!(vector::length(&membership_create_events) == 1, 1);
    }

    #[test]
    fun test_delete_membership() acquires  CommunityRegistry, Community, Membership {
        let secondUserName = string::utf8(b"second_user");
        let lCOMMUNITY_NAME = string::utf8(b"the bay");
        let lCOMMUNITY_DESCRIPTION = string::utf8(b"coolest");
        let resource_address = account::create_resource_address(&@bay, SEED);

        let admin_signer = account::create_account_for_test(@bay);
        let second_user = account::create_account_for_test(@0x7);
        let user = account::create_account_for_test(@0x4);
        let aptos_account =account::create_account_for_test(@0x1);
        let kade_account = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_account);

        usernames::dependancy_test_init_module(&kade_account);
        accounts::dependancy_test_init_module(&kade_account);
        init_module(&admin_signer);
        anchor::test_init_module(&admin_signer);

        usernames::claim_username(&user, string::utf8(b"bay"));
        usernames::claim_username(&second_user, secondUserName);
        accounts::create_account(&user, string::utf8(b"bay"));
        accounts::create_account(&second_user, secondUserName);
        anchor::mint(&admin_signer, signer::address_of(&user), COMMUNITY_CREATION_ANCHOR_AMOUNT);
        admin_create_community(&admin_signer, signer::address_of(&user), string::utf8(b"bay"), lCOMMUNITY_NAME, lCOMMUNITY_DESCRIPTION, lCOMMUNITY_DESCRIPTION );

        admin_create_membership(&admin_signer, signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);
        let mem_token = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);
        assert!(exists<Membership>(mem_token), EMEMBERSHIP_DOES_NOT_EXIST);

        admin_delete_membership(&admin_signer, signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);

        let membership_address = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);

        let membership_object_record = object::address_to_object<Membership>(membership_address);
        assert!(object::owns(membership_object_record, resource_address), 2);
        assert!(!object::owns(membership_object_record, signer::address_of(&user)), 3);


        let membership_delete_events = emitted_events<MembershipDeleteEvent>();
        assert!(vector::length(&membership_delete_events) == 1, 2);
    }

    #[test]
    fun test_delete_membership_and_reclaim() acquires  CommunityRegistry, Community, Membership {
        let secondUserName = string::utf8(b"second_user");
        let lCOMMUNITY_NAME = string::utf8(b"the bay");
        let lCOMMUNITY_DESCRIPTION = string::utf8(b"coolest");
        let resource_address = account::create_resource_address(&@bay, SEED);

        let admin_signer = account::create_account_for_test(@bay);
        let second_user = account::create_account_for_test(@0x7);
        let user = account::create_account_for_test(@0x4);
        let aptos_account =account::create_account_for_test(@0x1);
        let kade_account = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_account);

        usernames::dependancy_test_init_module(&kade_account);
        accounts::dependancy_test_init_module(&kade_account);
        init_module(&admin_signer);
        anchor::test_init_module(&admin_signer);

        usernames::claim_username(&user, string::utf8(b"bay"));
        usernames::claim_username(&second_user, secondUserName);
        accounts::create_account(&user, string::utf8(b"bay"));
        accounts::create_account(&second_user, secondUserName);

        anchor::mint(&admin_signer, signer::address_of(&user), COMMUNITY_CREATION_ANCHOR_AMOUNT);
        admin_create_community(&admin_signer,signer::address_of(&user), string::utf8(b"bay"), lCOMMUNITY_NAME, lCOMMUNITY_DESCRIPTION, lCOMMUNITY_DESCRIPTION );

        admin_create_membership(&admin_signer,signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);
        let mem_token = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);
        assert!(exists<Membership>(mem_token), EMEMBERSHIP_DOES_NOT_EXIST);

        admin_delete_membership(&admin_signer,signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);

        let membership_address = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);

        let membership_object_record = object::address_to_object<Membership>(membership_address);
        assert!(object::owns(membership_object_record, resource_address), 2);
        assert!(!object::owns(membership_object_record, signer::address_of(&user)), 3);

        admin_create_membership(&admin_signer, signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);
        let mem_token = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);
        assert!(exists<Membership>(mem_token), EMEMBERSHIP_DOES_NOT_EXIST);

        let membership_reclaim_event = emitted_events<MembershipReclaimEvent>();

        assert!(vector::length(&membership_reclaim_event) == 1, 5);

    }

    #[test]
    fun test_change_membership_type() acquires  CommunityRegistry, Community, Membership {
        let secondUserName = string::utf8(b"second_user");
        let lCOMMUNITY_NAME = string::utf8(b"the bay");
        let lCOMMUNITY_DESCRIPTION = string::utf8(b"coolest");
        let resource_address = account::create_resource_address(&@bay, SEED);

        let admin_signer = account::create_account_for_test(@bay);
        let second_user = account::create_account_for_test(@0x7);
        let user = account::create_account_for_test(@0x4);
        let aptos_account =account::create_account_for_test(@0x1);
        let kade_account = account::create_account_for_test(@kade);
        timestamp::set_time_has_started_for_testing(&aptos_account);

        usernames::dependancy_test_init_module(&kade_account);
        accounts::dependancy_test_init_module(&kade_account);
        init_module(&admin_signer);
        anchor::test_init_module(&admin_signer);
        usernames::claim_username(&user, string::utf8(b"bay"));
        usernames::claim_username(&second_user, secondUserName);
        accounts::create_account(&user, string::utf8(b"bay"));
        accounts::create_account(&second_user, secondUserName);

        anchor::mint(&admin_signer, signer::address_of(&user), COMMUNITY_CREATION_ANCHOR_AMOUNT);
        admin_create_community(&admin_signer, signer::address_of(&user), string::utf8(b"bay"), lCOMMUNITY_NAME, lCOMMUNITY_DESCRIPTION, lCOMMUNITY_DESCRIPTION );

        admin_create_membership(&admin_signer,signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME);
        let mem_token = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);
        assert!(exists<Membership>(mem_token), EMEMBERSHIP_DOES_NOT_EXIST);

        admin_change_membership(&admin_signer,signer::address_of(&user), string::utf8(b"bay"), signer::address_of(&second_user), secondUserName, lCOMMUNITY_NAME, 1 );

        let mem_token = token::create_token_address(&resource_address, &lCOMMUNITY_NAME, &secondUserName);
        let membership = borrow_global<Membership>(mem_token);

        assert!(membership.type == 1, 3);

        let membership_change_events = emitted_events<MembershipChangeEvent>();

        assert!(vector::length(&membership_change_events) == 1, 6);
    }

}
